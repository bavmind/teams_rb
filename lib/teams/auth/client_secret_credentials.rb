# frozen_string_literal: true

module Teams
  module Auth
    ClientSecretCredentials = Struct.new(:client_id, :client_secret, :tenant_id, keyword_init: true)
  end
end
