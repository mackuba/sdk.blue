require 'json'
require 'net/http'
require 'time'
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

  def get_response(url, retries: 3)
    uri = URI(url)
    attempts = 0

    loop do
      response = Net::HTTP.get_response(uri, request_headers)
      return response if attempts >= retries

      if rate_limited?(response, uri)
        delay = rate_limit_delay(response)
        puts "#{url} returned #{response}, retrying in #{delay} seconds"
        sleep delay
      elsif response.is_a?(Net::HTTPServerError)
        puts "#{url} returned #{response}, retrying"
        sleep 5
      else
        return response
      end

      attempts += 1
    end
  end


  private

  def rate_limited?(response, uri)
    response.code == '429' || github_rate_limited?(response, uri)
  end

  def github_rate_limited?(res, uri)
    res.code == '403' && uri.host == 'api.github.com' && (
      res['retry-after'] || res['x-ratelimit-remaining'] == '0' || res.body.to_s =~ /rate limit|abuse detection/i
    )
  end

  def rate_limit_delay(response)
    retry_after = response['retry-after']

    if retry_after && retry_after =~ /\A\d+\z/
      return retry_after.to_i
    end

    retry_at = parse_retry_date(retry_after) if retry_after

    if retry_at.nil? && [nil, '0'].include?(response['x-ratelimit-remaining'])
      reset = response['x-ratelimit-reset']
      retry_at = Time.at(reset.to_i) if reset&.match?(/\A\d+\z/)
    end

    retry_at ? [(retry_at - Time.now).ceil, 0].max : 60
  end

  def parse_retry_date(value)
    Time.httpdate(value)
  rescue ArgumentError
    nil
  end
end

class FetchError < StandardError
  attr_reader :response

  def initialize(response)
    super("Error: Invalid response for #{response.uri}: #{response}")
    @response = response
  end
end
