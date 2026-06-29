# frozen_string_literal: true

require "faraday"
require "json"

module Teams
  module Common
    class HttpClient
      attr_reader :base_url, :headers, :token

      def initialize(base_url: nil, headers: {}, token: nil, connection: nil)
        @base_url = base_url
        @headers = headers
        @token = token
        @connection = connection
      end

      def get(path, headers: {}, params: nil)
        request(:get, path, headers:, params:)
      end

      def post(path, json: nil, body: nil, headers: {}, params: nil)
        request(:post, path, json:, body:, headers:, params:)
      end

      def put(path, json: nil, body: nil, headers: {}, params: nil)
        request(:put, path, json:, body:, headers:, params:)
      end

      def delete(path, headers: {}, params: nil)
        request(:delete, path, headers:, params:)
      end

      def request(method, path, json: nil, body: nil, headers: {}, params: nil)
        resolved_token = resolve_token
        response = connection.public_send(method) do |request|
          request.url(path)
          request.params.update(params) if params
          request.headers.update(default_headers)
          request.headers.update(headers)
          request.headers["Authorization"] = "Bearer #{resolved_token}" if resolved_token

          if json
            request.headers["Content-Type"] ||= "application/json"
            request.body = JSON.generate(json)
          elsif body
            request.body = body
          end
        end

        parse_response(response)
      end

      def clone(base_url: nil, headers: nil, token: nil)
        self.class.new(
          base_url: base_url || self.base_url,
          headers: self.headers.merge(headers || {}),
          token: token || self.token,
          connection: @connection
        )
      end

      private

      def connection
        @connection ||= Faraday.new(url: base_url) do |faraday|
          faraday.adapter Faraday.default_adapter
        end
      end

      def default_headers
        { "User-Agent" => "teams_rb/#{Teams::VERSION}" }.merge(headers)
      end

      def resolve_token
        @resolved_token = token.respond_to?(:call) ? token.call : token
      end

      def parse_response(response)
        body = response.body.to_s
        parsed = begin
          body.empty? ? nil : JSON.parse(body)
        rescue JSON::ParserError
          body
        end

        if response.status < 200 || response.status >= 300
          message = "HTTP request failed with status #{response.status}"
          message = "#{message}: #{parsed}" if parsed && parsed != ""

          raise HttpError.new(
            message,
            status: response.status,
            headers: response.headers,
            body: parsed || body,
            request: response.env&.request
          )
        end

        parsed
      end
    end
  end
end
