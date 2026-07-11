# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "teams_rb"
  spec.version = "0.1.0"
  spec.authors = ["devran"]
  spec.summary = "Inoffical Ruby SDK for Microsoft Teams message bots"
  spec.description = "A Ruby-native SDK for receiving and sending Microsoft Teams bot messages from Rack/Rails apps."
  spec.license = "MIT"
  spec.homepage = "https://github.com/bavmind/teams_rb"
  spec.metadata["source_code_uri"] = "https://github.com/bavmind/teams_rb"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files = Dir["lib/**/*", "README.md", "PORT*.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.14"
  spec.add_dependency "rack", "~> 3.2"
  spec.add_dependency "base64", "~> 0.3"

  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "rack-test", "~> 2.2"
  spec.add_development_dependency "rake", ">= 13"
end
