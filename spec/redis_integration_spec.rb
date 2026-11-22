# frozen_string_literal: true

# Runs against a real Redis server (>= 6.2) when REDIS_URL is set, e.g.
#   REDIS_URL=redis://localhost:6379/15 bundle exec rspec
RSpec.describe 'Redis integration', if: ENV['REDIS_URL'] do
  before(:all) { require 'redis' }

  let(:redis)  { Redis.new(url: ENV['REDIS_URL']) }
  let(:prefix) { "rack-limits-spec-#{Process.pid}-#{rand(1 << 30)}" }
  let(:env)    { Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => '10.0.0.9') }

  after { redis.scan_each(match: "#{prefix}*") { |key| redis.del(key) } }

  def statuses(limiter, count)
    Array.new(count) { Thread.new { limiter.call(env.dup).first } }.map(&:value)
  end

  # A fresh connection per call, as a connection pool would provide.
  let(:cache) { -> { Thread.current[:spec_redis] ||= Redis.new(url: ENV['REDIS_URL']) } }

  it 'limits Hourly requests atomically across threads' do
    limiter = Rack::Limits::Hourly.new(example_target_app, max: 10, cache: cache, key_prefix: prefix)
    results = statuses(limiter, 40)
    expect(results.count(200)).to eq(10)
    key = redis.keys("#{prefix}*").first
    expect(redis.ttl(key)).to be_between(61, 3660)
  end

  it 'limits Interval requests atomically across threads' do
    limiter = Rack::Limits::Interval.new(example_target_app, min: 30, cache: cache, key_prefix: prefix)
    expect(statuses(limiter, 25).count(200)).to eq(1)
    expect(redis.pttl("#{prefix}:10.0.0.9")).to be_between(1, 30_000)
  end
end
