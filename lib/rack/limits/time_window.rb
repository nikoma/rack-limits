# frozen_string_literal: true

module Rack; module Limits
  ##
  # Base class for strategies that allow a fixed number of requests per
  # calendar window of time (see {Hourly} and {Daily}). Subclasses define
  # `#max_per_window` and `#window_ends_at`.
  class TimeWindow < Limiter
    ##
    # Returns `true` if fewer than the maximum number of requests permitted
    # for the current window of time have been made.
    #
    # The counter is incremented atomically (see {Limiter#cache_increment}),
    # so concurrent requests can never be allowed in excess of the limit.
    #
    # @param  [Rack::Request] request
    # @return [Boolean]
    def allowed?(request)
      cache_increment(cache_key(request), window_ttl) <= max_per_window.to_i
    rescue StandardError
      # Fail open if the cache backend is unavailable.
      true
    end

    ##
    # Returns the number of seconds until the current window resets.
    #
    # @return [Float]
    def retry_after
      window_ends_at - Time.now
    end

    ##
    # @return [Integer]
    def rate_limit
      max_per_window
    end

    protected

    ##
    # How long a counter needs to be kept by the cache: until the end of
    # the window, plus a margin for clock skew between application servers.
    #
    # @return [Integer]
    def window_ttl
      [retry_after.ceil, 0].max + 60
    end
  end
end; end
