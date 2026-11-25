require_relative 'cloned_repo'
require_relative 'requests'

require 'didkit'
require 'json'
require 'licensee'
require 'uri'

class TangledImport
  include ClonedRepo
  include ImportHelpers
  include Requests

  def initialize
    @user_cache = {}
  end

  def url_matches?(url)
    url =~ %r{^https://tangled\.org/@?[\w\-\.\:]+/[\w\-\.]+}
  end

  def import_url(url, project)
    url =~ %r{^https://tangled\.org/@?([\w\-\.\:]+)/([\w\-\.]+)}
    user, repo = $1, $2
    data = {}

    did = DID.resolve_handle(user)
    response = make_xrpc_request('org.tangled.repo.getRepoByName', { owner: did.did, name: repo })

    data['name'] = response['value']['declaration']['name'] || repo
    data['description'] = response['value']['description']
    data['user_login'] = did.document.get_verified_handle
    data['user_profile'] = "https://tangled.org/#{user}"

    repo_did = response['uri'].split('/')[2]
    repo_folder = clone_repo(user, repo, "https://tangled.org/#{user}/#{repo}")

    if tag_info = get_latest_tag(repo_folder)
      data['last_tag'] = tag_info
    end

    if license = get_license(repo_folder)
      data['license'] = license.spdx_id
    end

    data['stars'] = make_xrpc_request('org.tangled.feed.countStars', { subject: repo_did })['distinctAuthors']

    case project.language
    when :ruby
      gem = get_rubygems_releases(repo_folder, project).first
      update_last_release(data, gem)
    when :js
      npm = get_npm_releases(repo_folder, project).first
      update_last_release(data, npm)
    when :rust
      crate = get_cargo_releases(repo_folder, project).first
      update_last_release(data, crate)
    end

    data['last_commit'] = get_latest_commit(repo_folder)

    data
  end


  private

  def make_xrpc_request(method, params)
    uri = URI("https://api.tangled.org/xrpc/#{method}")
    uri.query = URI.encode_www_form(params)

    response = get_response(uri)
    raise FetchError.new(response) unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
