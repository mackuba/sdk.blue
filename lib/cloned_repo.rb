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
    package_names = Dir.glob(File.join(repo_folder, '**', 'package.json')).filter_map do |file|
      package = NPMImport::PackageJSON.new(File.read(file))
      next if package.version.nil? || package.private?

      package.name
    end

    NPMImport.new.get_releases(package_names, project.urls)
  end

  def get_cargo_releases(repo_folder, project)
    package_names = Dir.glob(File.join(repo_folder, '**', 'Cargo.toml')).filter_map do |file|
      package = CargoImport::CargoToml.new(File.read(file))
      package.name
    end

    CargoImport.new.get_releases(package_names, project.urls)
  end

  def get_rubygems_releases(repo_folder, project)
    gem_names = Dir.glob(File.join(repo_folder, '**', '*.gemspec')).filter_map do |file|
      gemspec = RubyGemsImport::Gemspec.new(File.read(file))
      gemspec.name
    end

    RubyGemsImport.new.get_releases(gem_names, project.urls)
  end

  def run_in_shell(directory)
    yield Shell.new(directory)
  end
end
