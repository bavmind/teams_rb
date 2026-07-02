# frozen_string_literal: true

module Teams
  module Api
    class QuotedReplyData < Model
      def message_id
        read("messageId", "message_id")
      end

      def sender_id
        read("senderId", "sender_id")
      end

      def sender_name
        read("senderName", "sender_name")
      end

      def preview
        read("preview")
      end

      def time
        read("time")
      end

      def is_reply_deleted
        read("isReplyDeleted", "is_reply_deleted")
      end

      def validated_message_reference
        read("validatedMessageReference", "validated_message_reference")
      end

      def to_h
        body = {}
        body["messageId"] = message_id if message_id
        body["senderId"] = sender_id if sender_id
        body["senderName"] = sender_name if sender_name
        body["preview"] = preview if preview
        body["time"] = time if time
        body["isReplyDeleted"] = is_reply_deleted unless is_reply_deleted.nil?
        body["validatedMessageReference"] = validated_message_reference unless validated_message_reference.nil?
        body
      end
    end

    class QuotedReplyEntity < Model
      def type
        "quotedReply"
      end

      def quoted_reply
        value = read("quotedReply", "quoted_reply")
        value.is_a?(QuotedReplyData) ? value : QuotedReplyData.new(value || {})
      end

      def to_h
        {
          "type" => type,
          "quotedReply" => quoted_reply.to_h
        }
      end
    end
  end
end
