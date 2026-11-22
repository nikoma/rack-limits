# frozen_string_literal: true

module Rack; module Limits
  ##
  # This rate limiter strategy throttles the application by enforcing a
  # minimum interval (by default, 1 second) between subsequent allowed HTTP
  # requests.
  #
  # @example Allowing up to two requests per second
  #   use Rack::Limits::Interval, :min => 0.5   #  500 ms interval
  #
  # @example Allowing a request every two seconds
  #   use Rack::Limits::Interval, :min => 2.0   # 2000 ms interval
  #
  class Interval < Limiter
    ##
    # @param  [#call]                  app
    # @param  [Hash{Symbol => Object}] options
    # @option options [Float] :min     (1.0)
    def initialize(app, options = {})
      super
    end

    ##
    # Returns `true` if sufficient time (equal to or more than
    # {#minimum_interval}) has passed since the last request and the given
    # present `request`.
    #
    # @param  [Rack::Request] request
    # @return [Boolean]
    def allowed?(request)
      t1 = request_start_time(request)
      t0 = cache_swap(cache_key(request), t1, minimum_interval)
      !t0 || (t1 - t0.to_f) >= minimum_interval
    rescue StandardError
      # If an error occurred while reading or updating the timestamp stored
      # in the cache, we fall back to allowing the request through. This
      # prevents the Rack application blowing up merely due to a backend
      # cache server (Memcached, Redis, etc.) being offline.
      true
    end

    ##
    # Returns the number of seconds before the client is allowed to retry an
    # HTTP request.
    #
    # @return [Float]
    def retry_after
      minimum_interval
    end

    ##
    # One request is allowed per {#minimum_interval}.
    #
    # @return [Integer]
    def rate_limit
      1
    end

    ##
    # Returns the required minimal interval (in terms of seconds) that must
    # elapse between two subsequent HTTP requests.
    #
    # @return [Float]
    def minimum_interval
      @min ||= (@options[:min] || 1.0).to_f
    end
  end
end; end
