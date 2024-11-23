require_relative 'requests'
require 'time'

class NPMImport
  include Requests

  class LocalPackage
    def initialize(json)
      @json = json
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

    def last_version
      @json['dist-tags']['latest']
    end

    def last_release_time
      Time.parse(@json['time'][last_version])
    end

    def repository_url
      @json['repository']['url']
    end
  end

  def get_package_info(name)
    response = get_response("https://registry.npmjs.com/#{name}")

    if response.code.to_i == 200
      RemotePackage.new(JSON.parse(response.body))
    elsif response.code.to_i == 404
      nil
    else
      raise FetchError.new(response)
    end
  end
end
