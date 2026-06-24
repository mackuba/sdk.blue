server "sdk.blue"

set :application, "sdk.blue"
set :repository, "https://tangled.org/mackuba.eu/sdk.blue"
set :keep_releases, 10
set :use_sudo, false
set :public_children, []

after 'deploy:update_code', 'deploy:link_shared'
before 'deploy:create_symlink', 'deploy:build'

namespace :deploy do
  task :link_shared do
    run "mkdir -p #{release_path}/config"
    run "ln -s #{shared_path}/auth.yml #{release_path}/config/auth.yml"
    run "ln -s #{shared_path}/metadata.yml #{release_path}/_data/metadata.yml"
    run "ln -s #{shared_path}/repos #{release_path}/tmp/repos"
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
