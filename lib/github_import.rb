require_relative 'npm_import'
require_relative 'requests'
require 'base64'

class GithubImport
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

  def import_url(url)
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

    if ['JavaScript', 'TypeScript'].include?(repo_info['language'])
      npm = get_npm_releases(user, repo)
      last_update = npm.map { |n| n.last_release_time }.sort.last

      if last_update && (release.nil? || last_update > release['published_at'])
        data['last_release'] = { 'published_at' => last_update }
      end
    end

    data['last_commit'] = get_latest_commit(user, repo)

    if user_info = get_user_info(user)
      data['user_name'] = user_info['name']
    end

    data
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

  def get_npm_releases(user, repo)
    search_url = URI("https://api.github.com/search/code")
    search_url.query = URI.encode_www_form(q: "repo:#{user}/#{repo} filename:package.json", per_page: 100)
    response = get_response(search_url)
    raise FetchError.new(response) unless response.code.to_i == 200

    json = JSON.parse(response.body)
    releases = []

    json['items'].each do |file|
      response = get_response(file['url'])
      raise FetchError.new(response) unless response.code.to_i == 200

      details = JSON.parse(response.body)
      contents = Base64.decode64(details['content'])
      package = NPMImport::LocalPackage.new(JSON.parse(contents))

      next if package.version.nil? || package.private?

      if npm = NPMImport.new.get_package_info(package.name)
        if npm.repository_url =~ %r{://github\.com/#{Regexp.escape(user)}/#{Regexp.escape(repo)}(\.git)?$}
          releases << npm
        end
      end
    end

    releases
  end
end
