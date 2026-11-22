# frozen_string_literal: true

require 'rack/test'
require 'rack/lint'
require 'rack/limits'

module SpecHelpers
  APP_BODY = 'Example App Body'

  def example_target_app
    ->(_env) { [200, { 'content-type' => 'text/plain' }, [APP_BODY]] }
  end

  # Wraps a limiter in Rack::Lint so every spec also checks Rack 3 SPEC
  # compliance of the responses it produces.
  def linted(limiter)
    Rack::Lint.new(limiter)
  end
end

# In-memory stand-in for a redis-rb client, with server-side atomicity.
class FakeRedis
  attr_reader :ttls

  def initialize
    @data, @ttls, @lock = {}, {}, Mutex.new
  end

  def get(key)
    @lock.synchronize { @data[key] }
  end

  def incr(key)
    @lock.synchronize { @data[key] = @data[key].to_i + 1 }
  end

  def expire(key, seconds)
    @lock.synchronize { @ttls[key] = seconds }
  end

  def set(key, value, get: false, px: nil)
    @lock.synchronize do
      previous = @data[key]
      @data[key] = value
      @ttls[key] = px / 1000.0 if px
      get ? previous : 'OK'
    end
  end
end

# A Hash whose reads are slow, which widens the window between reading and
# writing a counter so that a non-atomic implementation reliably races.
class SlowHash < Hash
  def [](key)
    value = super
    sleep 0.001
    value
  end
end

RSpec::Matchers.define :be_allowed do
  match { |response| response.status == 200 && response.body.include?(SpecHelpers::APP_BODY) }
  failure_message { |r| "expected an allowed response, got #{r.status}: #{r.body.inspect}" }
end

RSpec::Matchers.define :be_throttled do
  match { |response| response.status == 429 && response.body.include?('Rate Limit Exceeded') }
  failure_message { |r| "expected a throttled (429) response, got #{r.status}: #{r.body.inspect}" }
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.include Rack::Test::Methods
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
