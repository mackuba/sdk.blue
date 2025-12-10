require_relative 'requests'
require 'json'
require 'time'

class CargoImport
  include Requests

  class CargoToml
    def initialize(contents)
      @contents = contents
    end

    def name
      return unless package_section

      name_line = package_section.match(/^\s*name\s*=\s*"([^"]+)"/)
      name_line && name_line[1]
    end

    def package_section
      @package_section ||= begin
        match = @contents.match(/^\[package\](.+?)(^\[.+\]|\z)/m)
        match && match[1]
      end
    end
  end

  class RemoteCrate
    def initialize(json)
      @json = json
    end

    def name
      @json['crate']['name']
    end

    def last_release_time
      @json['versions'].map { |v| Time.parse(v['created_at']) }.sort.last
    end

    def homepage_url
      @json['crate']['homepage']
    end

    def repository_url
      @json['crate']['repository']
    end
  end

  def initialize
    @@cache ||= {}
  end

  def get_crate_info(name)
    sleep 1
    response = @@cache[name] || get_response("https://crates.io/api/v1/crates/#{name}")
    @@cache[name] = response

    if response.code.to_i == 200
      RemoteCrate.new(JSON.parse(response.body))
    elsif response.code.to_i == 404
      nil
    else
      raise FetchError.new(response)
    end
  end
end
