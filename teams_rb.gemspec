# frozen_string_literal: true

require_relative "lib/teams/version"

Gem::Specification.new do |spec|
  spec.name = "teams_rb"
  spec.version = Teams::VERSION
  spec.authors = ["Devran Cosmo Uenal"]
  spec.email = ["devran@bavmind.com"]

  spec.summary = "Unofficial Ruby SDK for building Microsoft Teams bots and apps"
  spec.description =
    "A Ruby-native port of the Microsoft Teams SDK concepts for building Teams bots and apps " \
    "from Rack/Rails: messaging, Adaptive Cards, dialogs, message extensions, streaming, " \
    "OAuth user sign-in, Microsoft Graph, and tab remote functions. An independent, " \
    "community-maintained project, not affiliated with or endorsed by Microsoft."
  spec.homepage = "https://github.com/bavmind/teams_rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "documentation_uri" => "#{spec.homepage}/tree/main/docs",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "docs/**/*", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.3"
  spec.add_dependency "faraday", "~> 2.14"
  spec.add_dependency "rack", "~> 3.2"

  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "rack-test", "~> 2.2"
  spec.add_development_dependency "rake", ">= 13"
end
