require 'json'
require 'net/http'
require 'uri'
require 'yaml'

module Requests
  AUTH_FILE = 'config/auth.yml'

  def auth_config
    @auth_config ||= begin
      config_path = File.join(__dir__, '..', AUTH_FILE)
      YAML.load(File.read(config_path))
    end
  end

  def request_headers
    { 'User-Agent' => "sdk.blue project info scanner (+https://sdk.blue) Ruby/#{RUBY_VERSION}"}
  end

  def get_response(url)
    Net::HTTP.get_response(URI(url), request_headers)
  end
end

class FetchError < StandardError
  attr_reader :response

  def initialize(response)
    super("Error: Invalid response for #{response.uri}: #{response}")
    @response = response
  end
end
