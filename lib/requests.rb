require 'net/http'
require 'uri'
require 'yaml'

module Requests
  AUTH_FILE = 'config/auth.yml'

  def config
    @config ||= begin
      config_path = File.join(__dir__, '..', AUTH_FILE)
      YAML.load(File.read(config_path))
    end
  end

  def get_response(url)
    auth_token = config['github_token']
    headers = { 'Authorization' => "Bearer #{auth_token}" }

    Net::HTTP.get_response(URI(url), headers)
  end
end

class FetchError < StandardError
  attr_reader :response

  def initialize(response)
    super("Error: Invalid response for #{response.uri}: #{response}")
    @response = response
  end
end
