# frozen_string_literal: true

require "set"

module Teams
  module OAuth
    # The default sign-in callback handlers, mirroring the TypeScript and
    # Python OAuth handlers: registered first on the signin routes, they
    # complete the flows, route each callback to its registered flow, fire
    # the sign-in events, and chain to user handlers via next. Their return
    # value is the invoke response; 412 tells the Teams client to fall back to
    # the interactive card.
    class Handlers
      EXPECTED_STATUSES = [400, 404, 412].freeze
      FAILURE_DETAIL = "unable to exchange token..."
      COMPLETED_TTL = ExchangeMarkers::TTL
      MAX_COMPLETED = 1000

      # How an owned token exchange settled, replayed to duplicates that
      # arrived while it ran.
      Outcome = Struct.new(:response, :error, :token_redeemed, keyword_init: true)

      class InFlight
        def initialize
          @mutex = Mutex.new
          @settled = ConditionVariable.new
          @outcome = nil
        end

        def settle(outcome)
          @mutex.synchronize do
            @outcome = outcome
            @settled.broadcast
          end
        end

        def wait
          @mutex.synchronize do
            @settled.wait(@mutex) until @outcome
            @outcome
          end
        end
      end

      attr_reader :pending_cache

      def initialize(app)
        @app = app
        @pending_cache = LocalPendingCache.new
        @mutex = Mutex.new
        @in_flight = {}
        @completed = {}
      end

      # signin/tokenExchange. Teams fans one exchange out to every endpoint
      # the user is signed in on, so repeats of an exchange id short-circuit:
      # a completed one answers 200 without re-emitting or chaining, and one
      # still running waits and mirrors the owner's result (412 if it raised).
      def token_exchange(ctx, nxt)
        exchange_id = ctx.activity.value.raw["id"]
        return run_token_exchange(ctx, nxt) if exchange_id.to_s.empty?

        waiting = nil
        owned = nil
        completed = false
        @mutex.synchronize do
          if (waiting = @in_flight[exchange_id])
            nil
          elsif completed_exchange?(ctx, exchange_id)
            completed = true
          else
            owned = @in_flight[exchange_id] = InFlight.new
          end
        end
        return await_exchange(ctx, exchange_id, waiting) if waiting
        return replay_completed_exchange(ctx, exchange_id) if completed

        run_owned_exchange(ctx, nxt, exchange_id, owned)
      end

      # signin/verifyState carries only a magic code, so the connections are
      # probed in order: pending sign-ins (newest first), the remaining
      # registered flows, then the default connection. A code a connection
      # rejects (400/404/412) moves on to the next; none accepting is a 404.
      def verify_state(ctx, nxt)
        code = ctx.activity.value.raw["state"]
        if code.to_s.empty?
          logger&.warn(
            "Auth state not present for conversation id '#{ctx.activity.conversation&.id}' " \
            "and user id '#{ctx.activity.from&.id}'."
          )
          return Response.new(status: 404)
        end

        verify_candidates(ctx).each do |connection_name, flow|
          terminal, response = verify_candidate(ctx, connection_name, flow, code)
          return response if terminal
        end
        Response.new(status: 404)
      ensure
        nxt.call
      end

      # signin/failure carries no connection name: it is attributed to the
      # newest pending sign-in that offered silent SSO. Without one, the
      # default connection is reported when no flows are registered;
      # otherwise the connection is unknown (nil) and every registered flow's
      # failure handlers are notified so none silently misses it.
      def failure(ctx, nxt)
        value = ctx.activity.value.raw
        target = pending_flows(ctx, sso_only: true).first
        registered = registry.to_a
        connection_name = if target
          target.connection_name
        elsif registered.empty?
          @app.default_connection_name
        end

        logger&.warn(
          "Sign-in failed: #{value["code"]} - #{value["message"]}. " \
          "If the code is 'resourcematchfailed', verify the Entra app registration's " \
          "Application ID URI matches the OAuth connection's Token Exchange URL."
        )
        callback_flows = target ? [target] : registered
        callback_flows.each { |flow| clear_pending(ctx, flow.connection_name) }

        @app.emit_error(Error.new("Sign-in failure: #{value["code"]} - #{value["message"]}"), activity: ctx.activity)
        event = SignInFailureEvent.new(context: ctx, connection_name:, code: value["code"], message: value["message"])
        @app.emit_sign_in_failure(event)
        callback_flows.each do |flow|
          flow_event = target ? event : event.dup.tap { |copy| copy.connection_name = flow.connection_name }
          flow.invoke_sign_in_failure_handlers(flow_event)
        end
        nil
      ensure
        nxt.call
      end

      private

      def registry
        @app.oauth_registry
      end

      def logger
        @app.logger
      end

      def run_owned_exchange(ctx, nxt, exchange_id, owned)
        outcome = nil
        begin
          response = run_token_exchange(ctx, nxt)
          outcome = Outcome.new(response:, token_redeemed: memory_completed?(exchange_id))
          response
        rescue StandardError => error
          outcome = Outcome.new(error:, token_redeemed: memory_completed?(exchange_id))
          raise
        ensure
          outcome ||= Outcome.new(error: Error.new("token exchange interrupted"), token_redeemed: false)
          @mutex.synchronize { @in_flight.delete(exchange_id) }
          owned.settle(outcome)
        end
      end

      def await_exchange(ctx, exchange_id, waiting)
        outcome = waiting.wait
        stamp_completed_exchange(ctx, exchange_id) if outcome.token_redeemed
        if outcome.error
          return Response.new(
            status: 412,
            body: {
              "id" => exchange_id,
              "connectionName" => resolved_connection_name(ctx.activity.value.raw["connectionName"]),
              "failureDetail" => outcome.error.message.to_s.empty? ? FAILURE_DETAIL : outcome.error.message
            }
          )
        end

        outcome.response.is_a?(Response) ? outcome.response : Response.new(status: 200)
      end

      def replay_completed_exchange(ctx, exchange_id)
        logger&.debug("Duplicate signin/tokenExchange with id '#{exchange_id}' - returning 200 no-op.")
        stamp_completed_exchange(ctx, exchange_id)
        Response.new(status: 200)
      end

      def run_token_exchange(ctx, nxt)
        activity = ctx.activity
        value = activity.value.raw
        connection_name = value["connectionName"]
        flow = registry[connection_name]
        event_connection_name = flow ? flow.connection_name : connection_name

        if flow.nil? && OAuth.lookup_key(connection_name) != OAuth.lookup_key(@app.default_connection_name)
          logger&.warn(
            "Sign-in token exchange invoked with connection name #{connection_name.inspect}, " \
            "but it is neither the default connection #{@app.default_connection_name.inspect} " \
            "nor a registered OAuth flow. Token verification will likely fail."
          )
        end

        begin
          token = ctx.api.users.exchange_token(
            user_id: activity.from.id,
            connection_name:,
            channel_id: activity.channel_id,
            exchange_request: { "token" => value["token"] }
          )
        rescue HttpError => error
          unless EXPECTED_STATUSES.include?(error.status)
            clear_pending(ctx, event_connection_name)
            logger&.error("Error exchanging token: #{error.message}")
            @app.emit_error(error, activity:)
            status = error.status || 500
            notify_terminal_failure(ctx, flow, error, status)
            return Response.new(status:)
          end

          logger&.info("Unable to exchange token: #{error.message}")
          return Response.new(
            status: 412,
            body: {
              "id" => value["id"],
              "connectionName" => connection_name,
              "failureDetail" => error.message.to_s.empty? ? FAILURE_DETAIL : error.message
            }
          )
        end

        record_completed_exchange(ctx, value["id"])
        clear_pending(ctx, event_connection_name)
        @app.emit_sign_in(ctx, token)
        flow&.invoke_sign_in_handlers(SignInEvent.new(context: ctx, token_response: token, connection_name: event_connection_name))
        nil
      ensure
        nxt.call
      end

      def verify_candidates(ctx)
        seen = Set.new
        candidates = []
        (pending_flows(ctx) + registry.to_a).each do |flow|
          key = OAuth.lookup_key(flow.connection_name)
          next if key.nil? || seen.include?(key)

          seen << key
          candidates << [flow.connection_name, flow]
        end

        default_flow = registry[@app.default_connection_name]
        default_name = default_flow ? default_flow.connection_name : @app.default_connection_name
        candidates << [default_name, default_flow] unless seen.include?(OAuth.lookup_key(default_name))
        candidates
      end

      # Returns [terminal, response]: a rejected code is not terminal.
      def verify_candidate(ctx, connection_name, flow, code)
        activity = ctx.activity
        token = ctx.api.users.get_token(
          user_id: activity.from.id,
          connection_name:,
          channel_id: activity.channel_id,
          code:
        )
        clear_pending(ctx, connection_name)
        @app.emit_sign_in(ctx, token)
        flow&.invoke_sign_in_handlers(SignInEvent.new(context: ctx, token_response: token, connection_name:))
        [true, nil]
      rescue HttpError => error
        if EXPECTED_STATUSES.include?(error.status)
          logger&.debug(
            "OAuth connection '#{connection_name}' did not accept the verify-state code (HTTP #{error.status})."
          )
          return [false, nil]
        end

        clear_pending(ctx, connection_name)
        logger&.error("Error verifying sign-in state: #{error.message}")
        @app.emit_error(error, activity:)
        status = error.status || 500
        notify_terminal_failure(ctx, flow, error, status)
        [true, Response.new(status:)]
      end

      def notify_terminal_failure(ctx, flow, error, status)
        return unless flow

        flow.invoke_sign_in_failure_handlers(
          SignInFailureEvent.new(
            context: ctx, connection_name: flow.connection_name, code: "tokenservice.http_#{status}", message: error.message
          )
        )
      end

      def pending_flows(ctx, sso_only: false)
        conversation_id, user_id = pending_scope(ctx)
        PendingSignIns.list(ctx.state, pending_cache, conversation_id:, user_id:).filter_map do |pending|
          next if sso_only && !pending.sso_offered

          flow = registry[pending.connection_name]
          unless flow
            logger&.debug(
              "Discarding pending OAuth sign-in state for connection '#{pending.connection_name}': no registered OAuth flow."
            )
            PendingSignIns.clear(ctx.state, pending_cache, pending.connection_name, conversation_id:, user_id:)
            next
          end
          flow
        end
      end

      def clear_pending(ctx, connection_name)
        conversation_id, user_id = pending_scope(ctx)
        PendingSignIns.clear(ctx.state, pending_cache, connection_name, conversation_id:, user_id:)
      end

      def pending_scope(ctx)
        [ctx.activity.conversation&.id, ctx.activity.from&.id]
      end

      def resolved_connection_name(connection_name)
        flow = registry[connection_name]
        flow ? flow.connection_name : connection_name
      end

      # Must be called while holding @mutex.
      def completed_exchange?(ctx, exchange_id)
        prune_completed
        return true if @completed.key?(exchange_id)

        ExchangeMarkers.completed?(ctx.state, exchange_id)
      rescue StandardError => error
        logger&.error("Unable to read persisted OAuth token exchange state; deduplicating in memory only: #{error.message}")
        false
      end

      def memory_completed?(exchange_id)
        @mutex.synchronize { @completed.key?(exchange_id) }
      end

      # The in-memory marker is authoritative on this instance; the state
      # marker (saved right away) lets another instance short-circuit too.
      def record_completed_exchange(ctx, exchange_id)
        return if exchange_id.to_s.empty?

        @mutex.synchronize do
          prune_completed
          @completed[exchange_id] = Time.now.to_f
          @completed.shift while @completed.size > MAX_COMPLETED
        end

        begin
          ExchangeMarkers.record(ctx.state, exchange_id)
          ctx.state&.save
        rescue StandardError => error
          logger&.error("Unable to persist completed OAuth token exchange; deduplicating in memory only: #{error.message}")
        end
      end

      # A duplicate's own turn state may predate the owner's write; saves are
      # last-write-wins, so the marker is copied into it to survive.
      def stamp_completed_exchange(ctx, exchange_id)
        ExchangeMarkers.record(ctx.state, exchange_id) unless ExchangeMarkers.completed?(ctx.state, exchange_id)
      rescue StandardError => error
        logger&.error("Unable to stamp completed OAuth token exchange into turn state: #{error.message}")
      end

      # Must be called while holding @mutex.
      def prune_completed
        cutoff = Time.now.to_f - COMPLETED_TTL
        @completed.delete_if { |_, completed_at| completed_at < cutoff }
      end
    end
  end
end
