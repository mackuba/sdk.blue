require_relative 'requests'
require 'json'

class GithubImport
  include Requests

  def initialize
    @user_cache = {}
  end

  def url_matches?(url)
    url =~ %r{^https://github\.com/[\w\-\.]+/[\w\-\.]+}
  end

  def import_url(url)
    url =~ %r{^https://github\.com/([\w\-\.]+)/([\w\-\.]+)}
    user, repo = $1, $2

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

    response = get_response("https://api.github.com/repos/#{user}/#{repo}/releases/latest")

    if response.code.to_i == 200
      json = JSON.parse(response.body)

      data['last_release'] = {
        'tag_name'     => json['tag_name'],
        'name'         => json['name'],
        'draft'        => json['draft'],
        'prerelease'   => json['prerelease'],
        'created_at'   => json['created_at'],
        'published_at' => json['published_at']
      }
    elsif response.code.to_i != 404
      raise FetchError.new(response)
    end

    response = get_response("https://api.github.com/repos/#{user}/#{repo}/tags")
    raise FetchError.new(response) unless response.code.to_i == 200

    json = JSON.parse(response.body)

    if tag = json.first
      tag_name = tag['name']
      response = get_response(tag['commit']['url'])
      raise FetchError.new(response) unless response.code.to_i == 200

      json = JSON.parse(response.body)
      data['last_tag'] = {
        'name'           => tag_name,
        'author_date'    => json['commit']['author']['date'],
        'committer_date' => json['commit']['committer']['date']
      }
    end

    response = get_response("https://api.github.com/repos/#{user}/#{repo}/commits")
    raise FetchError.new(response) unless response.code.to_i == 200

    json = JSON.parse(response.body)

    if commit = json.first
      data['last_commit'] = {
        'author_date'    => commit['commit']['author']['date'],
        'committer_date' => commit['commit']['committer']['date']
      }
    else
      raise FetchError.new(response)
    end

    if @user_cache[user].nil?
      response = get_response("https://api.github.com/users/#{user}")
      raise FetchError.new(response) unless response.code.to_i == 200

      json = JSON.parse(response.body)
      @user_cache[user] = json
    end

    data['user_name'] = @user_cache[user] && @user_cache[user]['name']

    data
  end
end
