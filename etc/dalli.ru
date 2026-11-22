$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rack/limits'
require 'dalli'

use Rack::Limits::Hourly, max: 100, cache: Dalli::Client.new('localhost:11211'), key_prefix: :limits

run lambda { |env| [200, {'content-type' => 'text/plain'}, ["Hello, world!\n"]] }
