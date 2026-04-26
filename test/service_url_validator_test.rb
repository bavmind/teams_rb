# frozen_string_literal: true

require_relative "test_helper"

class ServiceUrlValidatorTest < Minitest::Test
  def test_allows_public_teams_service_url
    validator = Teams::Auth::ServiceUrlValidator.new

    assert validator.validate!("https://smba.trafficmanager.net/teams")
  end

  def test_allows_configured_domain
    validator = Teams::Auth::ServiceUrlValidator.new(additional_allowed_domains: ["example.ngrok-free.app"])

    assert validator.validate!("https://example.ngrok-free.app/teams")
  end

  def test_rejects_missing_service_url
    validator = Teams::Auth::ServiceUrlValidator.new

    assert_raises(Teams::ServiceUrlError) { validator.validate!(nil) }
  end
end
