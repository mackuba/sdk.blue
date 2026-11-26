require_relative 'cargo_import'
require_relative 'hex_import'
require_relative 'import_helpers'
require_relative 'npm_import'
require_relative 'requests'
require_relative 'ruby_gems_import'

require 'base64'
require 'json'
require 'time'

class GithubImport
  include ImportHelpers
  include Requests

  def initialize
    @user_cache = {}
  end

  def request_headers
    { 'Authorization' => "Bearer " + auth_config['github_token'] }
  end

  def url_matches?(url)
    url =~ %r{^https://github\.com/[\w\-\.]+/[\w\-\.]+}
  end

  def import_url(url, project)
    url =~ %r{^https://github\.com/([\w\-\.]+)/([\w\-\.]+)}
    user, repo = $1, $2

    repo_info = get_repo_info(user, repo)
    data = extract_repo_data(repo_info)

    if release = get_latest_release(user, repo)
      data['last_release'] = release
    end

    if tag_info = get_latest_tag(user, repo)
      data['last_tag'] = tag_info
    end

    case project.language
    when :ruby
      gem = get_rubygems_releases(user, repo, project).first
      update_last_release(data, gem)
    when :js
      npm = get_npm_releases(user, repo, project).first
      update_last_release(data, npm)
    when :rust
      crate = get_cargo_releases(user, repo, project).first
      update_last_release(data, crate)
    when :gleam
      package = get_gleam_releases(user, repo, project).first
      update_last_release(data, package)
    when :elixir
      package = get_elixir_releases(user, repo, project).first
      update_last_release(data, package)
    end

    data['last_commit'] = get_latest_commit(user, repo)

    if user_info = get_user_info(user)
      data['user_name'] = user_info['name']
    end

    data
  end

  def update_last_release(data, package)
    return if package.nil?

    last_update = package.last_release_time
    release = data['last_release']

    if release.nil? || last_update > release['published_at']
      data['last_release'] = { 'published_at' => last_update }
    end
  end

  def get_repo_info(user, repo)
    response = get_response("https://api.github.com/repos/#{user}/#{repo}")
    raise FetchError.new(response) unless response.code.to_i == 200

    JSON.parse(response.body)
  end

  def extract_repo_data(json)
    data = {
      'name'         => json['name'],
      'description'  => json['description'],
      'user_login'   => json['owner']['login'],
      'user_profile' => "https://github.com/#{json['owner']['login']}",
      'homepage'     => json['homepage'],
      'stars'        => json['stargazers_count']
    }

    if json['license'] && json['license']['spdx_id'] != 'NOASSERTION'
      data['license'] = json['license']['spdx_id']
    end

    data
  end

  def get_latest_release(user, repo)
    response = get_response("https://api.github.com/repos/#{user}/#{repo}/releases/latest")

    if response.code.to_i == 200
      json = JSON.parse(response.body)

      {
        'tag_name'     => json['tag_name'],
        'name'         => json['name'],
        'draft'        => json['draft'],
        'prerelease'   => json['prerelease'],
        'created_at'   => Time.parse(json['created_at']),
        'published_at' => Time.parse(json['published_at'])
      }
    elsif response.code.to_i == 404
      nil
    else
      raise FetchError.new(response)
    end
  end

  def get_latest_tag(user, repo)
    response = get_response("https://api.github.com/repos/#{user}/#{repo}/tags")
    raise FetchError.new(response) unless response.code.to_i == 200

    json = JSON.parse(response.body)

    if tag = json.first
      tag_name = tag['name']
      response = get_response(tag['commit']['url'])
      raise FetchError.new(response) unless response.code.to_i == 200

      json = JSON.parse(response.body)
      {
        'name'           => tag_name,
        'author_date'    => Time.parse(json['commit']['author']['date']),
        'committer_date' => Time.parse(json['commit']['committer']['date'])
      }
    else
      nil
    end
  end

  def get_latest_commit(user, repo)
    response = get_response("https://api.github.com/repos/#{user}/#{repo}/commits")
    raise FetchError.new(response) unless response.code.to_i == 200

    json = JSON.parse(response.body)

    if commit = json.first
      {
        'author_date'    => Time.parse(commit['commit']['author']['date']),
        'committer_date' => Time.parse(commit['commit']['committer']['date'])
      }
    else
      raise FetchError.new(response)
    end
  end

  def get_user_info(user)
    @user_cache[user] ||= begin
      response = get_response("https://api.github.com/users/#{user}")
      raise FetchError.new(response) unless response.code.to_i == 200

      JSON.parse(response.body)
    end
  end

  def get_npm_releases(user, repo, project)
    files = find_package_configs(user, repo, 'package.json')

    package_names = files.filter_map do |file|
      package = NPMImport::PackageJSON.new(file[:contents])
      next if package.version.nil? || package.private?

      package.name
    end

    NPMImport.new.get_releases(package_names, project.urls)
  end

  def get_cargo_releases(user, repo, project)
    files = find_package_configs(user, repo, 'Cargo.toml')

    package_names = files.filter_map do |file|
      package = CargoImport::CargoToml.new(file[:contents])
      package.name
    end

    CargoImport.new.get_releases(package_names, project.urls)
  end

  def get_rubygems_releases(user, repo, project)
    files = find_package_configs(user, repo, '*.gemspec')

    gem_names = files.filter_map do |file|
      gemspec = RubyGemsImport::Gemspec.new(file[:contents])
      gemspec.name
    end

    RubyGemsImport.new.get_releases(gem_names, project.urls)
  end

  def get_gleam_releases(user, repo, project)
    files = find_package_configs(user, repo, 'gleam.toml')

    package_names = files.filter_map do |file|
      package = HexImport::GleamToml.new(file[:contents])
      package.name
    end

    HexImport.new.get_releases(package_names)
  end

  def get_elixir_releases(user, repo, project)
    files = find_package_configs(user, repo, 'mix.exs')

    package_names = files.filter_map do |file|
      package = HexImport::MixConfig.new(file[:contents])
      package.name
    end

    HexImport.new.get_releases(package_names)
  end

  def find_package_configs(user, repo, filename_pattern)
    tree_url = "https://api.github.com/repos/#{user}/#{repo}/git/trees/HEAD?recursive=1"
    response = get_response(tree_url, retries: 5)
    raise FetchError.new(response) unless response.code.to_i == 200

    json = JSON.parse(response.body)

    json['tree'].filter_map do |file|
      next unless file['type'] == 'blob' && file['mode'] != '120000'

      path = file['path']
      name = File.basename(path)
      next unless File.fnmatch?(filename_pattern, name)

      response = get_response(file['url'], retries: 5)
      raise FetchError.new(response) unless response.code.to_i == 200

      details = JSON.parse(response.body)
      contents = Base64.decode64(details['content'])

      { name: name, path: path, contents: contents }
    end
  end
end
