$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rack/limits'
require 'redis'

use Rack::Limits::Interval, min: 3.0, cache: Redis.new, key_prefix: :limits

run lambda { |env| [200, {'content-type' => 'text/plain'}, ["Hello, world!\n"]] }
