$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rack/limits'

use Rack::Limits::Interval, :min => 3.0, :cache => {}

run lambda { |env| [200, {'Content-Type' => 'text/plain'}, "Hello, world!\n"] }
