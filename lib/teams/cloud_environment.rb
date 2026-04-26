# frozen_string_literal: true

module Teams
  CloudEnvironment = Struct.new(
    :login_endpoint,
    :login_tenant,
    :bot_scope,
    :token_service_url,
    :open_id_metadata_url,
    :token_issuer,
    :graph_scope,
    :allowed_service_urls,
    keyword_init: true
  )

  PUBLIC_CLOUD = CloudEnvironment.new(
    login_endpoint: "https://login.microsoftonline.com",
    login_tenant: "botframework.com",
    bot_scope: "https://api.botframework.com/.default",
    token_service_url: "https://token.botframework.com",
    open_id_metadata_url: "https://login.botframework.com/v1/.well-known/openidconfiguration",
    token_issuer: "https://api.botframework.com",
    graph_scope: "https://graph.microsoft.com/.default",
    allowed_service_urls: [
      "smba.trafficmanager.net",
      "smba.onyx.prod.teams.trafficmanager.net",
      "smba.infra.gcc.teams.microsoft.com"
    ]
  )

  module CloudEnvironments
    module_function

    def public
      PUBLIC_CLOUD
    end

    def from_name(name)
      case name.to_s.downcase
      when "", "public"
        public
      else
        raise ConfigurationError, "unsupported cloud environment: #{name.inspect}"
      end
    end
  end
end
