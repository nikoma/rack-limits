# frozen_string_literal: true

RSpec.describe Rack::Limits::Hourly do
  let(:cache)   { {} }
  let(:limiter) { described_class.new(example_target_app, max_per_hour: 3, cache: cache) }
  let(:app)     { linted(limiter) }

  it 'is allowed if not seen this hour' do
    get '/foo'
    expect(last_response).to be_allowed
  end

  it 'is allowed if seen fewer than the max allowed per hour' do
    2.times { get '/foo' }
    expect(last_response).to be_allowed
  end

  it 'is allowed exactly up to the max allowed per hour' do
    3.times { get '/foo' }
    expect(last_response).to be_allowed
  end

  it 'is not allowed if seen more times than the max allowed per hour' do
    4.times { get '/foo' }
    expect(last_response).to be_throttled
  end

  it 'accepts :max as an alias' do
    limiter = described_class.new(example_target_app, max: 7)
    expect(limiter.max_per_window).to eq(7)
  end

  it 'keys counters by the current hour' do
    get '/foo'
    expect(cache.keys).to eq(["127.0.0.1:#{Time.now.strftime('%Y-%m-%dT%H')}"])
  end

  it 'sends Retry-After and RateLimit headers when throttled' do
    4.times { get '/foo' }
    now   = Time.now
    reset = 3600 - (now.min * 60 + now.sec)
    headers = last_response.headers
    expect(headers['retry-after'].to_i).to be_within(2).of(reset)
    expect(headers['ratelimit-reset']).to eq(headers['retry-after'])
    expect(headers['ratelimit-limit']).to eq('3')
    expect(headers['ratelimit-remaining']).to eq('0')
  end

  it 'gracefully allows the request if the cache bombs' do
    expect(limiter).to receive(:cache_get).and_raise(StandardError)
    get '/foo'
    expect(last_response).to be_allowed
  end

  context 'with a Redis-like cache' do
    let(:cache) { FakeRedis.new }

    it 'uses INCR and sets a TTL covering the rest of the window' do
      4.times { get '/foo' }
      expect(last_response).to be_throttled
      expect(cache.ttls.values.first).to be > 60
    end
  end

  context 'with a Dalli-like cache' do
    let(:cache) do
      Class.new do
        attr_reader :calls
        def initialize; @calls = []; @n = 0; end
        def incr(key, amt = 1, ttl = nil, default = nil)
          @calls << [key, amt, ttl, default]
          @n += amt
        end
      end.new
    end

    it 'uses incr with a TTL and an initial value' do
      4.times { get '/foo' }
      expect(last_response).to be_throttled
      _key, amt, ttl, default = cache.calls.first
      expect([amt, default]).to eq([1, 1])
      expect(ttl).to be > 60
    end
  end

  describe 'under concurrent requests' do
    let(:limiter) { described_class.new(example_target_app, max_per_hour: 10, cache: cache) }

    def statuses(count)
      env = Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => '10.0.0.9')
      Array.new(count) { Thread.new { limiter.call(env.dup).first } }.map(&:value)
    end

    [['a Hash', -> { SlowHash.new }], ['a Redis-like', -> { FakeRedis.new }]].each do |name, store|
      context "with #{name} cache" do
        let(:cache) { store.call }

        it 'never allows more than the maximum' do
          results = statuses(40)
          expect(results.count(200)).to eq(10)
          expect(results.count(429)).to eq(30)
        end
      end
    end
  end
end
