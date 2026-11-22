# frozen_string_literal: true

module Rack; module Limits
  ##
  # This is the base class for rate limiter implementations.
  #
  # @example Defining a rate limiter subclass
  #   class MyLimiter < Limiter
  #     def allowed?(request)
  #       # TODO: custom logic goes here
  #     end
  #   end
  #
  class Limiter
    ##
    # Guards read-modify-write sequences on caches that have no atomic
    # primitive of their own (e.g. a plain `Hash` or `GDBM`). This makes
    # those updates atomic across threads within one process; it cannot
    # coordinate separate processes. Use Redis or Memcached (Dalli) for
    # counters shared between processes or hosts.
    LOCK = Mutex.new

    DEFAULT_CODE    = 429
    DEFAULT_MESSAGE = 'Rate Limit Exceeded'

    attr_reader :app
    attr_reader :options

    ##
    # @param  [#call]                       app
    # @param  [Hash{Symbol => Object}]      options
    # @option options [Object]  :cache      (Hash.new)
    # @option options [Proc]    :key        (nil)
    # @option options [String]  :key_prefix (nil)
    # @option options [Integer] :code       (429)
    # @option options [String]  :message    ("Rate Limit Exceeded")
    def initialize(app, options = {})
      @app, @options = app, options.dup
    end

    ##
    # @param  [Hash{String => String}] env
    # @return [Array(Integer, Hash, #each)]
    # @see    https://github.com/rack/rack/blob/main/SPEC.rdoc
    def call(env)
      request = Rack::Request.new(env)
      allowed?(request) ? app.call(env) : rate_limit_exceeded
    end

    ##
    # Returns `false` if the rate limit has been exceeded for the given
    # `request`, or `true` otherwise.
    #
    # Override this method in subclasses that implement custom rate limiter
    # strategies.
    #
    # @param  [Rack::Request] request
    # @return [Boolean]
    def allowed?(request)
      case
        when whitelisted?(request) then true
        when blacklisted?(request) then false
        else true # override in subclasses
      end
    end

    ##
    # Returns `true` if the originator of the given `request` is whitelisted
    # (not subject to further rate limits).
    #
    # The default implementation always returns `false`. Override this
    # method in a subclass to implement custom whitelisting logic.
    #
    # @param  [Rack::Request] request
    # @return [Boolean]
    # @abstract
    def whitelisted?(request)
      false
    end

    ##
    # Returns `true` if the originator of the given `request` is blacklisted
    # (not honoring rate limits, and thus permanently forbidden access
    # without the need to maintain further rate limit counters).
    #
    # The default implementation always returns `false`. Override this
    # method in a subclass to implement custom blacklisting logic.
    #
    # @param  [Rack::Request] request
    # @return [Boolean]
    # @abstract
    def blacklisted?(request)
      false
    end

    protected

    ##
    # @return [Hash]
    def cache
      case cache = (options[:cache] ||= {})
        when Proc then cache.call
        else cache
      end
    end

    ##
    # @param  [String] key
    def cache_has?(key)
      case
        when cache.respond_to?(:has_key?)
          cache.has_key?(key)
        when cache.respond_to?(:get)
          cache.get(key) rescue false
        else false
      end
    end

    ##
    # @param  [String] key
    # @return [Object]
    def cache_get(key, default = nil)
      case
        when cache.respond_to?(:[])
          cache[key] || default
        when cache.respond_to?(:get)
          cache.get(key) || default
      end
    end

    ##
    # @param  [String] key
    # @param  [Object] value
    # @return [void]
    def cache_set(key, value)
      case
        when cache.respond_to?(:[]=)
          begin
            cache[key] = value
          rescue TypeError
            # GDBM throws a "TypeError: can't convert Float into String"
            # exception when trying to store a Float. On the other hand, we
            # don't want to unnecessarily coerce the value to a String for
            # any stores that do support other data types (e.g. in-memory
            # hash objects). So, this is a compromise.
            cache[key] = value.to_s
          end
        when cache.respond_to?(:set)
          cache.set(key, value)
      end
    end

    ##
    # Atomically increments the integer counter stored under `key` and
    # returns its new value. A missing counter starts from zero.
    #
    # * Redis-like stores (`#incr` + `#expire`) use `INCR`, and set a TTL
    #   when the counter is created.
    # * Dalli-like stores (`#incr(key, amount, ttl, initial)`) use the
    #   Memcached `incr` command with an initial value.
    # * Any other store is updated under {LOCK}.
    #
    # @param  [String]  key
    # @param  [Integer] ttl  seconds the counter needs to live
    # @return [Integer]
    def cache_increment(key, ttl)
      store = cache
      case
        when redis_like?(store)
          count = store.incr(key).to_i
          store.expire(key, ttl.ceil) if count == 1
          count
        when dalli_like?(store)
          store.incr(key, 1, ttl.ceil, 1).to_i
        else
          LOCK.synchronize do
            count = cache_get(key).to_i + 1
            cache_set(key, count)
            count
          end
      end
    end

    ##
    # Atomically stores `value` under `key` and returns the value that was
    # previously stored there (or `nil`).
    #
    # * Redis-like stores use `SET key value GET PX ttl` (Redis >= 6.2).
    # * Any other store is updated under {LOCK}.
    #
    # @param  [String]  key
    # @param  [Object]  value
    # @param  [Numeric] ttl  seconds the value needs to live
    # @return [Object, nil]
    def cache_swap(key, value, ttl)
      store = cache
      if redis_like?(store)
        store.set(key, value.to_s, get: true, px: (ttl * 1000).ceil)
      else
        LOCK.synchronize do
          previous = cache_get(key)
          cache_set(key, value)
          previous
        end
      end
    end

    ##
    # @param  [Rack::Request] request
    # @return [String]
    def cache_key(request)
      id = client_identifier(request)
      case
        when options.has_key?(:key)
          options[:key].call(request)
        when options.has_key?(:key_prefix)
          [options[:key_prefix], id].join(':')
        else id
      end
    end

    ##
    # @param  [Rack::Request] request
    # @return [String]
    def client_identifier(request)
      request.ip.to_s
    end

    ##
    # @param  [Rack::Request] request
    # @return [Float]
    def request_start_time(request)
      case
        when request.env.has_key?('HTTP_X_REQUEST_START')
          request.env['HTTP_X_REQUEST_START'].to_f / 1000
        else
          Time.now.to_f
      end
    end

    ##
    # Returns the rate-limit headers sent along with a throttled response.
    # Strategies that know their limit should override {#rate_limit} and
    # {#retry_after}.
    #
    # @return [Hash{String => String}]
    def rate_limit_headers
      headers = {}
      if respond_to?(:retry_after)
        seconds = [retry_after.to_f.ceil, 0].max.to_s
        headers['retry-after']     = seconds
        headers['ratelimit-reset'] = seconds
      end
      if respond_to?(:rate_limit)
        headers['ratelimit-limit']     = rate_limit.to_i.to_s
        headers['ratelimit-remaining'] = '0'
      end
      headers
    end

    ##
    # Outputs a `Rate Limit Exceeded` error.
    #
    # @return [Array(Integer, Hash, #each)]
    def rate_limit_exceeded
      http_error(options[:code] || DEFAULT_CODE,
                 options[:message] || DEFAULT_MESSAGE,
                 rate_limit_headers)
    end

    ##
    # Outputs an HTTP `4xx` or `5xx` response.
    #
    # @param  [Integer]                code
    # @param  [String, #to_s]          message
    # @param  [Hash{String => String}] headers
    # @return [Array(Integer, Hash, #each)]
    def http_error(code, message = nil, headers = {})
      [ code,
        { 'content-type' => 'text/plain; charset=utf-8' }.merge(headers),
        [ http_status(code) + (message.nil? ? "\n" : " (#{message})\n") ]
      ]
    end

    ##
    # Returns the standard HTTP status message for the given status `code`.
    #
    # @param  [Integer] code
    # @return [String]
    def http_status(code)
      [code, Rack::Utils::HTTP_STATUS_CODES[code]].join(' ')
    end

    private

    def redis_like?(store)
      store.respond_to?(:incr) && store.respond_to?(:expire)
    end

    def dalli_like?(store)
      store.respond_to?(:incr) && store.method(:incr).parameters.size >= 4
    end
  end
end; end
