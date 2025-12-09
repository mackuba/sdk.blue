require_relative 'npm_import'
require_relative 'requests'

require 'didkit'
require 'fileutils'
require 'licensee'
require 'minisky'

class TangledImport
  include Requests

  def initialize
    @user_cache = {}
  end

  def url_matches?(url)
    url =~ %r{^https://tangled\.org/@[\w\-\.]+/[\w\-\.]+}
  end

  def import_url(url)
    url =~ %r{^https://tangled\.org/@([\w\-\.]+)/([\w\-\.]+)}
    user, repo = $1, $2

    did = DID.resolve_handle(user)
    sky = Minisky.new(did.get_document.pds_endpoint, nil)

    repos = sky.fetch_all('com.atproto.repo.listRecords',
      { repo: did, collection: 'sh.tangled.repo', limit: 100 },
      field: 'records'
    )

    repo_record = repos.detect { |x| x['value']['name'] == repo }

    repo_folder = clone_repo(user, repo)

    data = repo_data_from_record(repo_record['value'])
    data['user_login'] = user
    data['user_profile'] = "https://tangled.org/@#{user}"

    if tag_info = get_latest_tag(repo_folder)
      data['last_tag'] = tag_info
    end

    if (license = Licensee.license(repo_folder)) && license.spdx_id != 'NOASSERTION'
      data['license'] = license.spdx_id
    end

    data['stars'] = get_stars(repo_record['uri'])

    data['last_commit'] = get_latest_commit(repo_folder)

    data
  end

  def clone_repo(user, repo)
    repos_cache = File.expand_path(File.join(__dir__, '..', 'tmp', 'repos'))
    FileUtils.mkdir_p(repos_cache)

    dirname = "#{user}_#{repo}"
    repo_folder = File.join(repos_cache, dirname)

    if Dir.exist?(repo_folder)
      Dir.chdir(repo_folder) do
        system('git pull -q')
      end
    else
      Dir.chdir(repos_cache) do
        system("git clone https://tangled.org/@#{user}/#{repo} #{dirname}")
      end
    end

    repo_folder
  end

  def repo_data_from_record(record)
    {
      'name'        => record['name'],
      'description' => record['description'],
    }
  end

  def get_latest_tag(repo_folder)
    Dir.chdir(repo_folder) do
      newest_tag_commit = %x(git rev-list --tags --max-count=1).strip
      return nil if newest_tag_commit.empty?

      newest_tag = %x(git tag --points-at "#{newest_tag_commit}" | head -1).strip
      timestamp = %x(git show -s --format=%cI "#{newest_tag_commit}").strip

      {
        'name' => newest_tag,
        'committer_date' => Time.parse(timestamp)
      }
    end
  end

  def get_latest_commit(repo_folder)
    Dir.chdir(repo_folder) do
      {
        'committer_date' => %x(git show -s --format=%cI).strip.then { |x| Time.parse(x) },
        'author_date' => %x(git show -s --format=%aI).strip.then { |x| Time.parse(x) }
      }
    end
  end

  def get_stars(repo_record_uri)
    url = URI("https://constellation.microcosm.blue/links/count")
    url.query = URI.encode_www_form(target: repo_record_uri, collection: 'sh.tangled.feed.star', path: '.subject')

    response = get_response(url)
    raise FetchError.new(response) unless response.code.to_i == 200

    json = JSON.parse(response.body)
    json['total']
  end
end
