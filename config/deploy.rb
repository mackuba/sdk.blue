# TODO: migrate to capistrano3 bundler integration
require 'bundler/capistrano'
set :bundle_dir, ''
set :bundle_flags, '--quiet'
set :bundle_without, []

set :application, "sdk.blue"
set :repository, "https://github.com/mackuba/sdk.blue.git"
set :scm, :git
set :keep_releases, 10
set :use_sudo, false
set :deploy_to, "/var/www/sdk.blue"
set :deploy_via, :remote_cache
set :public_children, []

server "blue.mackuba.eu", :app, :web, :db, :primary => true

before 'bundle:install', 'deploy:set_bundler_options'

after 'deploy:update_code', 'deploy:link_shared'
before 'deploy:create_symlink', 'deploy:build'
after 'deploy', 'deploy:cleanup'

namespace :deploy do
  task :set_bundler_options do
    run "cd #{release_path} && bundle config set --local deployment 'true'"
    run "cd #{release_path} && bundle config set --local path '#{shared_path}/bundle'"
    run "cd #{release_path} && bundle config set --local without 'development test'"
  end

  task :link_shared do
    run "mkdir -p #{release_path}/config"
    run "ln -s #{shared_path}/auth.yml #{release_path}/config/auth.yml"
    run "ln -s #{shared_path}/github_info.yml #{release_path}/_data/github_info.yml"
  end

  task :build do
    run "cd #{release_path} && RACK_ENV=production bundle exec jekyll build"
  end

  task :migrate do
  end

  task :fetch_metadata do
    run "export RACK_ENV=production; cd #{current_path} && bundle exec rake fetch_metadata && bundle exec jekyll build"
  end

  task :with_fetch do
    update_code

    run "cd #{release_path} && RACK_ENV=production bundle exec rake fetch_metadata"

    create_symlink
    cleanup
  end
end
