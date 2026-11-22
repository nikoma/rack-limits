# frozen_string_literal: true

require_relative 'lib/rack/limits/version'

Gem::Specification.new do |spec|
  spec.name        = 'rack-limits'
  spec.version     = Rack::Limits::VERSION::STRING
  spec.summary     = 'HTTP request rate limiter for Rack applications.'
  spec.description = 'Rack middleware for rate-limiting incoming HTTP requests ' \
                     'by minimum interval, or by maximum requests per hour or ' \
                     'per day. A maintained fork of rack-throttle.'
  # Original rack-throttle authors, followed by the rack-limits maintainer.
  spec.authors     = ['Arto Bendiken', 'Brendon Murphy', 'Nikolai Manek']
  spec.email       = ['niko.manek@gmail.com']
  spec.homepage    = 'https://github.com/nikoma/rack-limits'
  spec.license     = 'Unlicense'

  spec.metadata = {
    'homepage_uri'          => spec.homepage,
    'source_code_uri'       => spec.homepage,
    'bug_tracker_uri'       => "#{spec.homepage}/issues",
    'changelog_uri'         => "#{spec.homepage}/blob/master/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*.rb'] + %w[README.md CHANGELOG.md AUTHORS UNLICENSE]
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.2'
  spec.add_dependency 'rack', '>= 3.0', '< 4'
end
