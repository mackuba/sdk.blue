require_relative 'requests'
require 'json'

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

    data = get_repo_info(user, repo)

    if release = get_latest_release(user, repo)
      data['last_release'] = release
    end

    if tag_info = get_latest_tag(user, repo)
      data['last_tag'] = tag_info
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

    json = JSON.parse(response.body)

    data = {
      'name'        => json['name'],
      'description' => json['description'],
      'user_login'  => json['owner']['login'],
      'homepage'    => json['homepage'],
      'stars'       => json['stargazers_count']
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
        'created_at'   => json['created_at'],
        'published_at' => json['published_at']
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
        'author_date'    => json['commit']['author']['date'],
        'committer_date' => json['commit']['committer']['date']
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
        'author_date'    => commit['commit']['author']['date'],
        'committer_date' => commit['commit']['committer']['date']
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
end
