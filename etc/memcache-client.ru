$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rack/limits'
gem 'memcache-client'
require 'memcache'

use Rack::Limits::Interval, :min => 3.0, :cache => MemCache.new('localhost:11211')

run lambda { |env| [200, {'Content-Type' => 'text/plain'}, "Hello, world!\n"] }
