require_relative 'requests'

require 'json'
require 'time'
require 'uri'

class RubyGemsImport
  include Requests

  class Gemspec
    def initialize(contents)
      @contents = contents
    end

    def name
      if @contents =~ /^\s*[a-zA-Z_][a-zA-Z0-9_]*\.name\s*=\s*('[^']+'|"[^"]+")/
        return $1[1..-2]
      end
    end
  end

  class RemoteGem
    def initialize(json)
      @json = json
    end

    def name
      @json['name']
    end

    def last_release_time
      Time.parse(@json['version_created_at'])
    end
  end

  def initialize
    @@cache ||= {}
  end

  def get_gem_info(name)
    encoded_name = URI.encode_www_form_component(name)
    response = @@cache[name] || get_response("https://rubygems.org/api/v1/gems/#{encoded_name}.json")
    @@cache[name] = response

    if response.code.to_i == 200
      RemoteGem.new(JSON.parse(response.body))
    elsif response.code.to_i == 404
      nil
    else
      raise FetchError.new(response)
    end
  end
end
