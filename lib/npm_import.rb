require_relative 'requests'
require 'json'
require 'time'

class NPMImport
  include Requests

  class PackageJSON
    def initialize(data)
      @json = JSON.parse(data)
    end

    def name
      @json['name']
    end

    def version
      @json['version']
    end

    def private?
      @json['private']
    end
  end

  class RemotePackage
    def initialize(json)
      @json = json
    end

    def name
      @json['name']
    end

    def last_version
      @json['dist-tags']['latest']
    end

    def last_release_time
      Time.parse(@json['time'][last_version])
    end

    def homepage_url
      @json['homepage']
    end

    def repository_url
      @json.dig('repository', 'url')
    end

    def inspect
      fields = [:name, :last_version, :last_release_time].map { |v| "#{v}=#{self.send(v).inspect}" }.join(", ")
      "#<#{self.class}:0x#{object_id} #{fields}>"
    end
  end

  def initialize
    @@cache ||= {}
  end

  def get_package_info(name)
    response = @@cache[name] || get_response("https://registry.npmjs.com/#{name}")
    @@cache[name] = response

    if response.code.to_i == 200
      RemotePackage.new(JSON.parse(response.body))
    elsif response.code.to_i == 404
      nil
    else
      raise FetchError.new(response)
    end
  end
end
