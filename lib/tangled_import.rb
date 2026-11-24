require_relative 'cargo_import'
require_relative 'import_helpers'
require_relative 'npm_import'
require_relative 'requests'
require_relative 'ruby_gems_import'

require 'didkit'
require 'fileutils'
require 'json'
require 'licensee'
require 'time'

class TangledImport
  include ImportHelpers
  include Requests

  class Shell
    def initialize(working_directory)
      @working_directory = working_directory
    end

    def run(*command)
      system(*command, chdir: @working_directory, exception: true)
    end

    def read(*command)
      invocation = (command.length == 1) ? command.first : command
      output = IO.popen(invocation, chdir: @working_directory, &:read)
      status = $?
      raise "Command failed (#{status}): #{command.join(' ')}" unless status.success?

      output
    end
  end

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
    repo_folder = clone_repo(user, repo)

    if tag_info = get_latest_tag(repo_folder)
      data['last_tag'] = tag_info
    end

    if (license = Licensee.license(repo_folder)) && license.spdx_id != 'NOASSERTION'
      data['license'] = license.spdx_id
    end

    data['stars'] = make_xrpc_request('org.tangled.feed.countStars', { subject: repo_did })['distinctAuthors']

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
      run_in_shell(repo_folder) do |sh|
        sh.run('git fetch -q --prune origin')
        sh.run('git reset -q --hard @{upstream}')
        sh.run('git clean -ffd')
      end
    else
      run_in_shell(repos_cache) do |sh|
        sh.run('git', 'clone', "https://tangled.org/#{user}/#{repo}", dirname)
      end
    end

    repo_folder
  end

  def get_latest_tag(repo_folder)
    run_in_shell(repo_folder) do |sh|
      newest_tag_commit = sh.read('git rev-list --tags --max-count=1').strip
      return nil if newest_tag_commit.empty?

      tags = sh.read('git', 'tag', '--points-at', newest_tag_commit)
      timestamp = sh.read('git', 'show', '-s', '--format=%cI', newest_tag_commit)

      {
        'name' => tags.lines.first.to_s.strip,
        'committer_date' => Time.parse(timestamp.strip)
      }
    end
  end

  def get_latest_commit(repo_folder)
    dates = run_in_shell(repo_folder) { |sh| sh.read('git show -s --format=%cI%n%aI') }
    committer_date, author_date = dates.lines.map(&:strip)

    {
      'committer_date' => Time.parse(committer_date),
      'author_date' => Time.parse(author_date)
    }
  end

  def get_npm_releases(repo_folder, project)
    packages = run_in_shell(repo_folder) { |sh| sh.read('find . -name package.json') }
    releases = []

    packages.each_line do |file|
      contents = File.read(File.join(repo_folder, file.chomp))
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

  def get_cargo_releases(repo_folder, project)
    packages = run_in_shell(repo_folder) { |sh| sh.read('find . -name Cargo.toml') }
    releases = []

    packages.each_line do |file|
      contents = File.read(File.join(repo_folder, file.chomp))
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


  private

  def run_in_shell(directory)
    yield Shell.new(directory)
  end

  def make_xrpc_request(method, params)
    uri = URI("https://api.tangled.org/xrpc/#{method}")
    uri.query = URI.encode_www_form(params)

    response = get_response(uri)
    raise FetchError.new(response) unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
