# frozen_string_literal: true

RSpec.describe Rack::Limits::Interval do
  let(:cache)   { {} }
  let(:limiter) { described_class.new(example_target_app, min: 0.1, cache: cache) }
  let(:app)     { linted(limiter) }

  it 'allows the request if the source has not been seen' do
    get '/foo'
    expect(last_response).to be_allowed
  end

  it 'allows the request if the source has not been seen in the current interval' do
    get '/foo', {}, 'HTTP_X_REQUEST_START' => '1000000'
    get '/foo', {}, 'HTTP_X_REQUEST_START' => '1000200'
    expect(last_response).to be_allowed
  end

  it 'does not allow the request if the source has been seen inside the current interval' do
    get '/foo', {}, 'HTTP_X_REQUEST_START' => '1000000'
    get '/foo', {}, 'HTTP_X_REQUEST_START' => '1000050'
    expect(last_response).to be_throttled
  end

  it 'sends Retry-After and RateLimit headers when throttled' do
    limiter = described_class.new(example_target_app, min: 2.5)
    app = linted(limiter)
    Rack::MockRequest.new(app).get('/')
    response = Rack::MockRequest.new(app).get('/')
    expect(response.status).to eq(429)
    expect(response.headers).to include(
      'retry-after'         => '3',
      'ratelimit-limit'     => '1',
      'ratelimit-remaining' => '0',
      'ratelimit-reset'     => '3'
    )
  end

  it 'gracefully allows the request if the cache bombs on getting' do
    expect(limiter).to receive(:cache_get).and_raise(StandardError)
    get '/foo'
    expect(last_response).to be_allowed
  end

  it 'gracefully allows the request if the cache bombs on setting' do
    expect(limiter).to receive(:cache_set).and_raise(StandardError)
    get '/foo'
    expect(last_response).to be_allowed
  end

  context 'with a Redis-like cache' do
    let(:cache) { FakeRedis.new }

    it 'swaps the timestamp atomically and sets a millisecond TTL' do
      get '/foo'
      expect(last_response).to be_allowed
      get '/foo'
      expect(last_response).to be_throttled
      expect(cache.ttls.values).to all(eq(0.1))
    end
  end

  describe 'under concurrent requests' do
    let(:limiter) { described_class.new(example_target_app, min: 60, cache: cache) }

    def statuses(count)
      env = Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => '10.0.0.9')
      Array.new(count) { Thread.new { limiter.call(env.dup).first } }.map(&:value)
    end

    context 'with a Hash cache' do
      let(:cache) { SlowHash.new }

      it 'allows exactly one request per interval' do
        expect(statuses(25).count(200)).to eq(1)
      end
    end

    context 'with a Redis-like cache' do
      let(:cache) { FakeRedis.new }

      it 'allows exactly one request per interval' do
        expect(statuses(25).count(200)).to eq(1)
      end
    end
  end
end
