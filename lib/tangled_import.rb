require_relative 'cargo_import'
require_relative 'import_helpers'
require_relative 'npm_import'
require_relative 'requests'
require_relative 'ruby_gems_import'

require 'didkit'
require 'fileutils'
require 'json'
require 'licensee'
require 'minisky'
require 'time'

class TangledImport
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

    did = DID.resolve_handle(user)
    sky = Minisky.new(did.document.pds_host, nil)

    repos = sky.fetch_all('com.atproto.repo.listRecords',
      { repo: did, collection: 'sh.tangled.repo', limit: 100 },
      field: 'records'
    )

    repo_record = repos.detect { |x| x['value']['name'] == repo || x['uri'].split('/').last == repo }

    repo_folder = clone_repo(user, repo)

    data = repo_data_from_record(repo_record)
    data['user_login'] = user.start_with?('did:') && DID.new(user).document.get_verified_handle || user
    data['user_profile'] = "https://tangled.org/#{user}"

    if tag_info = get_latest_tag(repo_folder)
      data['last_tag'] = tag_info
    end

    if (license = Licensee.license(repo_folder)) && license.spdx_id != 'NOASSERTION'
      data['license'] = license.spdx_id
    end

    data['stars'] = get_stars(repo_record)

    if project.language == :ruby
      gems = get_rubygems_releases(repo_folder, project)
      last_update = gems.map { |gem| gem.last_release_time }.sort.last
      tag_date = tag_info && tag_info['committer_date']

      if last_update && (tag_date.nil? || last_update > tag_date)
        data['last_release'] = { 'published_at' => last_update }
      end
    elsif project.language == :js
      npm = get_npm_releases(repo_folder, project)
      last_update = npm.map { |n| n.last_release_time }.sort.last

      if last_update
        data['last_release'] = { 'published_at' => last_update }
      end
    elsif project.language == :rust
      crates = get_cargo_releases(repo_folder, project)
      last_update = crates.map { |c| c.last_release_time }.sort.last

      if last_update
        data['last_release'] = { 'published_at' => last_update }
      end
    end

    data['last_commit'] = get_latest_commit(repo_folder)

    data
  end

  def clone_repo(user, repo)
    repos_cache = File.expand_path(File.join(__dir__, '..', 'tmp', 'repos'))
    FileUtils.mkdir_p(repos_cache)

    dirname = "#{user.gsub(':', '_')}_#{repo}"
    repo_folder = File.join(repos_cache, dirname)

    if Dir.exist?(repo_folder)
      Dir.chdir(repo_folder) do
        system('git pull -q')
      end
    else
      Dir.chdir(repos_cache) do
        system("git clone https://tangled.org/#{user}/#{repo} #{dirname}")
      end
    end

    repo_folder
  end

  def repo_data_from_record(record)
    {
      'name'        => record['value']['name'] || record['uri'].split('/').last,
      'description' => record['value']['description'],
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

  def get_stars(repo_record)
    stars = get_stars_for_target(repo_record['uri'], '.subject')
    stars += get_stars_for_target(repo_record['value']['repoDid'], '.subject.did') if repo_record['value']['repoDid']
    stars
  end

  def get_stars_for_target(target, path)
    url = URI("https://constellation.microcosm.blue/links/count")
    url.query = URI.encode_www_form(target: target, collection: 'sh.tangled.feed.star', path: path)

    response = get_response(url)
    raise FetchError.new(response) unless response.code.to_i == 200

    json = JSON.parse(response.body)
    json['total']
  end

  def get_npm_releases(repo_folder, project)
    Dir.chdir(repo_folder) do
      packages = %x(find . -name 'package.json').strip
      releases = []

      packages.lines.each do |file|
        contents = File.read(file.strip)
        package = NPMImport::PackageJSON.new(contents)

        next if package.version.nil? || package.private?

        if npm = NPMImport.new.get_package_info(package.name)
          package_repo_url = normalize_repo_url(npm.repository_url)
          package_homepage = normalize_repo_url(npm.homepage_url)

          if project.urls.map { |u| normalize_repo_url(u) }.any? { |u| u == package_repo_url || u == package_homepage }
            releases << npm
          end
        end
      end

      releases
    end
  end

  def get_cargo_releases(repo_folder, project)
    Dir.chdir(repo_folder) do
      packages = %x(find . -name 'Cargo.toml').strip
      releases = []

      packages.lines.each do |file|
        contents = File.read(file.strip)
        package = CargoImport::CargoToml.new(contents)

        next if package.name.nil?

        if crate = CargoImport.new.get_crate_info(package.name)
          crate_repo_url = normalize_repo_url(crate.repository_url)
          crate_homepage = normalize_repo_url(crate.homepage_url)

          if project.urls.map { |u| normalize_repo_url(u) }.any? { |u| u == crate_repo_url || u == crate_homepage }
            releases << crate
          end
        end
      end

      releases
    end
  end

  def get_rubygems_releases(repo_folder, project)
    releases = []

    Dir[File.join(repo_folder, '*.gemspec')].sort.each do |gemspec_file|
      gemspec = RubyGemsImport::Gemspec.new(File.read(gemspec_file))
      next unless gemspec.name

      if gem = RubyGemsImport.new.get_gem_info(gemspec.name)
        releases << gem
      end
    end

    releases
  end
end
