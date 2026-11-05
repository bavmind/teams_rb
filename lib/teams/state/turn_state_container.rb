# frozen_string_literal: true

module Teams
  module State
    # The state scopes loaded for one turn, exposed as ctx.state, with the
    # identity they were loaded for. Mirrors the TypeScript, Python, and .NET
    # turn state containers.
    #
    # conversation is always present; user is nil when the activity has no
    # from identity. conversation_id/user_id are fixed at construction so a
    # save always targets the keys the scopes were loaded from.
    class TurnStateContainer
      attr_reader :conversation, :user, :conversation_id, :user_id

      def initialize(conversation:, conversation_id:, user: nil, user_id: nil, deleter: nil, saver: nil)
        @conversation = conversation
        @conversation_id = conversation_id
        @user = user
        @user_id = user_id
        @deleter = deleter
        @saver = saver
      end

      # Seals every scope so post-turn access raises.
      def seal
        conversation.seal
        user&.seal
        self
      end

      # Removes both scopes from storage immediately, then clears them in
      # memory so the rest of the turn sees the deletion.
      def delete
        raise Error, "State deletion is not available: state is not enabled for this app." unless @deleter

        @deleter.call
        conversation.clear.mark_clean
        user&.clear&.mark_clean
        nil
      end

      # Persists dirty scopes; called by the app at the end of the turn.
      def save
        @saver&.call(self)
        nil
      end

      def inspect
        "#<#{self.class.name} conversation=#{conversation.inspect} conversation_id=#{conversation_id.inspect} " \
          "user=#{user.inspect} user_id=#{user_id.inspect}>"
      end
    end
  end
end
