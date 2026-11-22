$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rack/limits'
require 'gdbm' # gem 'gdbm' (no longer bundled with Ruby since 3.1)

use Rack::Limits::Interval, min: 3.0, cache: GDBM.new('/tmp/limits.db')

run lambda { |env| [200, {'content-type' => 'text/plain'}, ["Hello, world!\n"]] }
