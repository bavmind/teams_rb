# frozen_string_literal: true

module Teams
  class HttpStream
    STREAM_CHANNEL_DATA_KEYS = %w[streamId streamType streamSequence].freeze

    attr_reader :app, :conversation_reference

    def initialize(app:, conversation_reference:)
      @app = app
      @conversation_reference = conversation_reference
      reset_state
      @result = nil
      @canceled = false
      @timed_out = false
      @chunk_handlers = []
      @close_handlers = []
    end

    # Registers a handler called with the SentActivity of every stream chunk.
    # Handlers persist across stream reuse.
    def on_chunk(&handler)
      @chunk_handlers << handler
      self
    end

    # Registers a handler called with the final SentActivity when the stream
    # closes. Handlers persist across stream reuse.
    def on_close(&handler)
      @close_handlers << handler
      self
    end

    def canceled
      @canceled
    end

    def timed_out
      @timed_out
    end

    def closed
      !@result.nil?
    end

    def count
      @queue.length
    end

    def sequence
      @sequence
    end

    def emit(activity_or_text)
      raise StreamCancelledError, "Stream has been cancelled." if canceled

      # Emitting after close reopens the stream: start a new streamed message
      # on the same instance. The canceled flag stays sticky across reuse.
      reset_for_next_stream if closed

      @queue << normalize_activity(activity_or_text)
      flush
    end

    def update(text)
      emit(
        "type" => "typing",
        "text" => text,
        "channelData" => { "streamType" => "informative" }
      )
    end

    def clear_text
      @text = +""
      @queue.reject! { |activity| activity["type"] == "message" }
      @final_activity = nil
    end

    def close
      return @result if closed
      return nil if canceled

      begin
        flush
      rescue StreamCancelledError
        return nil
      end

      return nil if canceled
      return nil unless final_content?

      # Merging the sent activity with the response keeps the id available
      # even though live Teams answers follow-up stream posts with 202 and an
      # empty body. @result doubling as the closed flag depends on this.
      @result = if @timed_out
        send_final
      else
        begin
          outbound = final_stream_activity
          Api::SentActivity.merge(outbound, send_activity(outbound))
        rescue StreamTimedOutError
          # The final streamed send tripped the two-minute limit. Update the
          # original message in place with the buffered content instead of
          # posting a duplicate.
          send_final
        end
      end

      @close_handlers.each { |handler| handler.call(@result) }
      @result
    ensure
      reset_state if @result
    end

    private

    def reset_state
      @id = nil
      @text = +""
      @sequence = 1
      @channel_data = {}
      @final_activity = nil
      @queue = []
    end

    def reset_for_next_stream
      reset_state
      @result = nil
      @timed_out = false
    end

    def flush
      while (activity = @queue.shift)
        if informative_update?(activity)
          next unless @text.empty?

          @channel_data = merge_channel_data(activity["channelData"])
          send_stream_chunk(activity)
          next
        end

        next unless activity["type"] == "message"

        text = activity["text"].to_s if activity.key?("text")
        @text << text if text
        @final_activity = activity
        @channel_data = merge_channel_data(activity["channelData"])

        next if @text.empty?
        next if text.nil? || text.empty?

        send_stream_chunk(
          "type" => "typing",
          "text" => @text
        )
      end
    end

    def send_stream_chunk(activity)
      return if @timed_out

      body = activity.dup
      body["id"] = @id if @id

      channel_data = merge_channel_data(body["channelData"])
      channel_data["streamId"] ||= @id if @id
      # The chunk's own stream type wins; merged channel data must not leak a
      # previous informative marker into regular streaming chunks.
      channel_data["streamType"] = activity.dig("channelData", "streamType") || "streaming"
      channel_data["streamSequence"] ||= @sequence
      body["channelData"] = channel_data

      body["entities"] = replace_streaminfo_entity(
        body["entities"],
        compact_hash(
          "type" => "streaminfo",
          "streamId" => @id,
          "streamType" => channel_data["streamType"],
          "streamSequence" => channel_data["streamSequence"]
        )
      )

      result = begin
        send_activity(body)
      rescue StreamTimedOutError
        # A timed-out chunk is swallowed; close sends the buffered content by
        # updating the original message in place.
        return
      end

      sent = Api::SentActivity.merge(body, result)
      @chunk_handlers.each { |handler| handler.call(sent) }
      @sequence += 1
      @id ||= sent.id
    end

    def final_stream_activity
      activity = (@final_activity || { "type" => "message" }).dup
      activity["type"] = "message"
      activity["id"] = @id if @id
      if !@text.empty? || activity.key?("text")
        activity["text"] = @text
      else
        activity.delete("text")
      end

      channel_data = merge_channel_data(activity["channelData"], "streamType" => "final")
      channel_data.delete("streamSequence")
      channel_data["streamId"] ||= @id if @id
      activity["channelData"] = channel_data unless channel_data.empty?

      activity["entities"] = replace_streaminfo_entity(
        activity["entities"],
        "type" => "streaminfo",
        "streamId" => @id,
        "streamType" => "final"
      )

      activity
    end

    # Sends the buffered content as a plain final message. Drops the
    # streaminfo entity and stream channel data so the send routes through
    # update (reusing the stream id) instead of creating a duplicate message.
    def send_final
      activity = (@final_activity || { "type" => "message" }).dup
      activity["type"] = "message"
      activity["id"] = @id if @id
      if !@text.empty? || activity.key?("text")
        activity["text"] = @text
      else
        activity.delete("text")
      end

      entities = Array(activity["entities"]).reject do |entity|
        entity.is_a?(Hash) && entity["type"] == "streaminfo"
      end
      entities.empty? ? activity.delete("entities") : activity["entities"] = entities

      strip_stream_channel_data(activity, activity["channelData"] || {})

      Api::SentActivity.merge(activity, send_activity(activity))
    end

    # Removes the stream markers from channel data for the timed-out in-place
    # final, so the send is treated as a normal message edit (.NET behavior).
    def strip_stream_channel_data(body, channel_data)
      remaining = channel_data.reject { |key, _value| STREAM_CHANNEL_DATA_KEYS.include?(key) }
      remaining.empty? ? body.delete("channelData") : body["channelData"] = remaining
      body
    end

    def send_activity(activity)
      raise StreamCancelledError, "Stream has been cancelled." if canceled

      body = activity.dup
      body["from"] = conversation_reference.bot.to_h if conversation_reference.bot
      body["conversation"] = conversation_reference.conversation.to_h

      # Stream chunks and the streamed final carry a streaminfo entity and are
      # always created; only the timed-out in-place final routes through update.
      if body["id"] && !streaminfo_entity?(body)
        app.api.conversations.update_activity(
          conversation_reference.conversation_id,
          body["id"],
          body,
          service_url: conversation_reference.service_url
        )
      else
        app.api.conversations.create_activity(
          conversation_reference.conversation_id,
          body,
          service_url: conversation_reference.service_url
        )
      end
    rescue HttpError => error
      raise_stream_error(error)
    end

    def raise_stream_error(error)
      raise error unless error.status == 403

      message = stream_error_message(error)
      normalized = message.downcase

      if normalized.include?("exceeded streaming time")
        @timed_out = true
        raise StreamTimedOutError, message.empty? ? "Stream exceeded the streaming time limit." : message
      elsif normalized.include?("cancel")
        @canceled = true
        raise StreamCancelledError, message.empty? ? "Teams channel stopped the stream." : message
      elsif normalized.include?("not allowed") && !normalized.include?("completed streamed message")
        raise StreamNotAllowedError, message.empty? ? "Streaming is not allowed for the user or bot." : message
      else
        raise TerminalStreamError, message.empty? ? "Teams returned a streaming error." : message
      end
    end

    def stream_error_message(error)
      body = error.body
      return "" unless body.is_a?(Hash)

      body.dig("error", "message").to_s
    end

    def streaminfo_entity?(body)
      Array(body["entities"]).any? do |entity|
        entity.is_a?(Hash) && entity["type"] == "streaminfo"
      end
    end

    def informative_update?(activity)
      activity["type"] == "typing" && activity.dig("channelData", "streamType") == "informative"
    end

    def final_content?
      return true unless @text.empty?

      activity = @final_activity
      return false unless activity

      attachments = activity["attachments"]
      suggested_actions = activity["suggestedActions"]

      (attachments.respond_to?(:empty?) && !attachments.empty?) ||
        (suggested_actions.respond_to?(:empty?) && !suggested_actions.empty?)
    end

    def normalize_activity(activity_or_text)
      case activity_or_text
      when String
        Api::MessageActivity.new(activity_or_text).to_h
      when Cards::AdaptiveCard
        Api::MessageActivity.new.add_card(activity_or_text).to_h
      when Hash
        Common::Hashes.deep_stringify_keys(activity_or_text)
      else
        activity_or_text.respond_to?(:to_h) ? activity_or_text.to_h : activity_or_text
      end
    end

    def merge_channel_data(value, overrides = {})
      (@channel_data || {}).merge(value || {}).merge(overrides)
    end

    def replace_streaminfo_entity(entities, stream_entity)
      remaining = Array(entities).reject do |entity|
        entity.is_a?(Hash) && entity["type"] == "streaminfo"
      end
      remaining << stream_entity
      remaining
    end

    def compact_hash(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key] = value unless value.nil?
      end
    end
  end
end
