require_relative 'cargo_import'
require_relative 'import_helpers'
require_relative 'npm_import'
require_relative 'ruby_gems_import'
require_relative 'shell'

require 'fileutils'
require 'time'

module ClonedRepo
  include ImportHelpers

  def clone_repo(user, repo, git_url)
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
        sh.run('git', 'clone', git_url, dirname)
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

  def get_license(repo_folder)
    license = Licensee.license(repo_folder)
    return nil if license.nil? || license.spdx_id == 'NOASSERTION'

    license
  end

  def update_last_release(data, package)
    return if package.nil?

    data['last_release'] = { 'published_at' => package.last_release_time }
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

    releases.sort_by(&:last_release_time).reverse
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

    releases.sort_by(&:last_release_time).reverse
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

    releases.sort_by(&:last_release_time).reverse
  end

  def run_in_shell(directory)
    yield Shell.new(directory)
  end
end
