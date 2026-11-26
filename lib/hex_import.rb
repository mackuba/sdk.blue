require_relative 'requests'

require 'json'
require 'time'
require 'uri'

class HexImport
  include Requests

  class GleamToml
    def initialize(contents)
      @contents = contents
    end

    def name
      metadata = @contents.each_line.take_while { |line| line !~ /^\s*\[/ }.join
      metadata[/^\s*name\s*=\s*(["'])([a-z][a-z0-9_]*)\1/, 2]
    end
  end

  class MixConfig
    def initialize(contents)
      @contents = contents.lines.reject { |line| line.lstrip.start_with?('#') }.join
    end

    def name
      project = function_body('project')
      return unless project

      package_value = project[/(?:^|[\[,])\s*package:\s*(.*)/m, 1]

      package = if package_value&.start_with?('[')
        keyword_list(package_value)
      elsif helper = package_value&.[](/\A([a-z_]\w*)(?:\(\))?(?=\s*[,\]])/, 1)
        function_body(helper)
      end

      if package&.match?(/(?:^|[\[,])\s*name:/)
        package[/(?:^|[\[,])\s*name:\s*"([a-z][a-z0-9_]*)"\s*(?=[,\]])/, 1]
      else
        project[/(?:^|[\[,])\s*app:\s*:([a-z][a-z0-9_]*)\s*(?=[,\]])/, 1]
      end
    end

    private

    def function_body(name)
      @contents[
        /^([ \t]*)defp?\s+#{Regexp.escape(name)}(?:\(\))?\s*(?:,\s*do:|do\b)(.*?)(?=^\1(?:end\b|defp?\s)|\z)/m, 2
      ]
    end

    def keyword_list(contents)
      depth = 0

      contents.to_enum(:scan, /"(?:\\.|[^"\\])*"|#[^\n]*|\[|\]/).each do |token|
        depth += 1 if token == '['
        next unless token == ']'

        depth -= 1
        return contents[0...Regexp.last_match.end(0)] if depth.zero?
      end
    end
  end

  class RemotePackage
    def initialize(json)
      @json = json
    end

    def name
      @json['name']
    end

    def last_release_time
      @json.fetch('releases').map { |release| Time.iso8601(release.fetch('inserted_at')) }.max
    end
  end

  def initialize
    @@cache ||= {}
  end

  def get_package_info(name)
    encoded_name = URI.encode_www_form_component(name)
    response = @@cache[name] || get_response("https://hex.pm/api/packages/#{encoded_name}")

    case response.code.to_i
    when 200
      @@cache[name] = response
      RemotePackage.new(JSON.parse(response.body))
    when 404
      @@cache[name] = response
      nil
    else
      raise FetchError.new(response)
    end
  end

  def get_releases(package_names)
    releases = package_names.uniq.filter_map { |name| get_package_info(name) }

    releases.sort_by(&:last_release_time).reverse
  end
end
