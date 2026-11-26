require_relative 'import_helpers'
require_relative 'requests'

require 'json'
require 'time'
require 'uri'

class RubyGemsImport
  include ImportHelpers
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

    def homepage_url
      @json['homepage_uri']
    end

    def repository_url
      @json['source_code_uri']
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

  def get_releases(gem_names, project_urls)
    repo_urls = project_urls.map { |url| normalize_repo_url(url) }
    releases = []

    gem_names.uniq.each do |name|
      if gem = get_gem_info(name)
        if package_matches_repo?(gem, repo_urls)
          releases << gem
        end
      end
    end

    releases.sort_by(&:last_release_time).reverse
  end
end
