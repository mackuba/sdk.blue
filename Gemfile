source "https://rubygems.org"

gem "jekyll", "~> 4.3"

gem 'minisky', '~> 0.5'
gem 'didkit', '~> 0.2'

group :jekyll_plugins do
end

# dependency of net-ssh and jekyll - remove when jekyll is updated
gem 'logger'

group :development do
  gem 'capistrano', '~> 2.0'

  # for net-ssh
  gem 'ed25519', '>= 1.2', '< 2.0'
  gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0'

  # dependency of capistrano
  gem 'benchmark'
end
