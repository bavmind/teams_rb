# frozen_string_literal: true

module Teams
  class HttpStream
    attr_reader :app, :conversation_reference

    def initialize(app:, conversation_reference:)
      @app = app
      @conversation_reference = conversation_reference
      reset_state
      @result = nil
      @canceled = false
    end

    def canceled
      @canceled
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
      raise StreamCancelledError, "Teams channel stopped the stream." if canceled

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

      flush

      return nil if canceled
      return nil unless final_content?

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

      @result = send_activity(activity)
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
      body = activity.dup
      body["id"] = @id if @id

      channel_data = merge_channel_data(body["channelData"])
      channel_data["streamId"] ||= @id if @id
      channel_data["streamType"] ||= "streaming"
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

      result = send_activity(body)
      @sequence += 1
      @id ||= extract_id(result)
    end

    def send_activity(activity)
      app.send_activity(conversation_reference, activity)
    rescue HttpError => error
      if error.status == 403
        @canceled = true
        raise StreamCancelledError, "Teams channel stopped the stream."
      end

      raise
    end

    def extract_id(result)
      return unless result.is_a?(Hash)

      result["id"] || result[:id]
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
        activity_or_text.dup
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
