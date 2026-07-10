# frozen_string_literal: true

require "json"
require "rack/request"

module Teams
  class RackApp
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      return not_found unless request.post? && request.path_info == @app.messaging_endpoint

      body = request.body.read
      payload = body.empty? ? {} : JSON.parse(body)
      response = @app.process_inbound(payload, env:)
      rack_response(response)
    rescue JSON::ParserError
      rack_response(Response.new(status: 400, body: { error: "invalid JSON" }))
    rescue BadRequestError, AuthenticationError => error
      rack_response(Response.new(status: error_status(error), body: { error: error.message }))
    rescue StandardError => error
      @app.logger.error("Error processing Teams activity: #{error.class}: #{error.message}")
      rack_response(Response.new(status: 500, body: { error: "Internal server error" }))
    end

    private

    def not_found
      [404, { "content-type" => "text/plain" }, ["Not Found"]]
    end

    def rack_response(response)
      body = response.body
      body = body.nil? ? "" : JSON.generate(body)
      headers = { "content-type" => "application/json" }.merge(response.headers)
      [response.status, headers, [body]]
    end

    def error_status(error)
      case error
      when AuthenticationError
        401
      else
        400
      end
    end
  end
end
