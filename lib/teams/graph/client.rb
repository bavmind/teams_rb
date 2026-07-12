# frozen_string_literal: true

module Teams
  module Graph
    # Thin Microsoft Graph HTTP client, following the TypeScript SDK's core
    # Graph client (Python/.NET delegate to the official Graph SDKs, which
    # Ruby lacks a maintained equivalent of; TypeScript's generated endpoint
    # packages are out of scope, so the raw request surface is the API here,
    # like TypeScript's client.http escape hatch).
    class Client
      DEFAULT_BASE_URL_ROOT = "https://graph.microsoft.com"

      attr_reader :base_url_root, :version, :http

      # token: a string or a callable returning one (an app-only Graph token
      # or a user token from sign-in). base_url_root overrides the Graph host
      # for sovereign clouds (e.g. "https://graph.microsoft.us").
      def initialize(token:, base_url_root: nil, version: "v1.0", http: nil)
        @base_url_root = (base_url_root || DEFAULT_BASE_URL_ROOT).sub(%r{/+\z}, "")
        @version = version
        @http = http || Common::HttpClient.new(token:)
      end

      def get(path, params: nil)
        request { http.get(url(path), params:) }
      end

      def post(path, json: nil, params: nil)
        request { http.post(url(path), json: stringify(json), params:) }
      end

      def patch(path, json: nil, params: nil)
        request { http.patch(url(path), json: stringify(json), params:) }
      end

      def put(path, json: nil, params: nil)
        request { http.put(url(path), json: stringify(json), params:) }
      end

      def delete(path, params: nil)
        request { http.delete(url(path), params:) }
      end

      private

      def request
        yield
      rescue HttpError => error
        graph_error = error.body.is_a?(Hash) ? error.body["error"] : nil
        message = if graph_error.is_a?(Hash) && graph_error["message"]
          "Graph request failed (#{error.status}): #{graph_error["message"]}"
        else
          "Graph request failed with status #{error.status}"
        end

        raise GraphError.new(
          message,
          status: error.status,
          code: graph_error.is_a?(Hash) ? graph_error["code"] : nil,
          body: error.body
        )
      end

      def url(path)
        "#{base_url_root}/#{version}/#{path.to_s.sub(%r{\A/+}, "")}"
      end

      def stringify(json)
        json.is_a?(Hash) ? Common::Hashes.deep_stringify_keys(json) : json
      end
    end
  end
end
