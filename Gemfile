# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'rack', ENV.fetch('RACK_VERSION', '~> 3.2')
gem 'rack-test', '~> 2.1'
gem 'rake', '~> 13.0'
gem 'rspec', '~> 3.13'

# Only needed for the Redis integration spec (run when REDIS_URL is set).
gem 'redis', '~> 5.0', require: false
