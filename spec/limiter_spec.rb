# frozen_string_literal: true

RSpec.describe Rack::Limits::Limiter do
  let(:limiter) { described_class.new(example_target_app, options) }
  let(:options) { {} }
  let(:app)     { linted(limiter) }

  describe 'basic calling' do
    it 'returns the example app' do
      get '/foo'
      expect(last_response).to be_allowed
    end

    it 'calls the application if allowed' do
      expect(limiter).to receive(:allowed?).and_return(true)
      get '/foo'
      expect(last_response).to be_allowed
    end

    it 'responds with 429 Too Many Requests by default if not allowed' do
      expect(limiter).to receive(:allowed?).and_return(false)
      get '/foo'
      expect(last_response).to be_throttled
      expect(last_response.body).to eq("429 Too Many Requests (Rate Limit Exceeded)\n")
      expect(last_response.headers['content-type']).to eq('text/plain; charset=utf-8')
    end

    context 'with a custom :code and :message' do
      let(:options) { { code: 503, message: 'Slow down' } }

      it 'uses them' do
        expect(limiter).to receive(:allowed?).and_return(false)
        get '/foo'
        expect(last_response.status).to eq(503)
        expect(last_response.body).to eq("503 Service Unavailable (Slow down)\n")
      end
    end
  end

  describe 'allowed?' do
    it 'returns true if whitelisted' do
      expect(limiter).to receive(:whitelisted?).and_return(true)
      get '/foo'
      expect(last_response).to be_allowed
    end

    it 'returns false if blacklisted' do
      expect(limiter).to receive(:blacklisted?).and_return(true)
      get '/foo'
      expect(last_response).to be_throttled
    end

    it 'returns true if not whitelisted or blacklisted' do
      expect(limiter).to receive(:whitelisted?).and_return(false)
      expect(limiter).to receive(:blacklisted?).and_return(false)
      get '/foo'
      expect(last_response).to be_allowed
    end
  end

  describe 'cache keys' do
    it 'does not mutate the options hash passed in' do
      opts = {}
      described_class.new(example_target_app, opts).send(:cache)
      expect(opts).to be_empty
    end

    it 'supports :key_prefix' do
      limiter = described_class.new(example_target_app, key_prefix: :limits)
      request = Rack::Request.new(Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => '10.0.0.1'))
      expect(limiter.send(:cache_key, request)).to eq('limits:10.0.0.1')
    end
  end
end
