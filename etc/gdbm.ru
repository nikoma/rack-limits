$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rack/limits'
require 'gdbm'

use Rack::Limits::Interval, :min => 3.0, :cache => GDBM.new('/tmp/limits.db')

run lambda { |env| [200, {'Content-Type' => 'text/plain'}, "Hello, world!\n"] }
