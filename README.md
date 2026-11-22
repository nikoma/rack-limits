HTTP Request Rate Limiter for Rack Applications
===============================================

[![CI](https://github.com/nikoma/rack-limits/actions/workflows/ci.yml/badge.svg)](https://github.com/nikoma/rack-limits/actions/workflows/ci.yml)

This is [Rack][] middleware that provides logic for rate-limiting incoming
HTTP requests to Rack applications. You can use `Rack::Limits` with any
Ruby web framework based on Rack, including Ruby on Rails, Sinatra, Hanami
and Roda.

`Rack::Limits` is a maintained fork of [rack-throttle][], originally written
by Arto Bendiken and Brendon Murphy. The original authors were busy with
other projects (yes, I asked Arto), so this fork exists to keep the code
working on current Ruby and Rack and to accept pull requests.

* <https://github.com/nikoma/rack-limits>

Features
--------

* Limits a Rack application by enforcing a minimum time interval between
  subsequent HTTP requests from a particular client, as well as by defining
  a maximum number of allowed HTTP requests per a given time period (hourly
  or daily).
* Responds with `429 Too Many Requests` plus `Retry-After` and `RateLimit-*`
  headers when a limit is exceeded.
* Updates counters atomically, so concurrent requests can't get past a
  limit (see [Concurrency and atomicity](#concurrency-and-atomicity)).
* Works with any Rack 3 application and any Rack-based framework.
* Stores rate-limiting counters in any key/value store that responds to
  `#[]`/`#[]=` (like Ruby's hashes) or to `#get`/`#set`, with native atomic
  support for [Redis][redis] and Memcached via [Dalli][dalli].
* Compatible with the [gdbm][] gem.

Requirements
------------

* Ruby >= 3.2
* [Rack][] >= 3.0, < 4 (tested against 3.0, 3.1 and 3.2)
* Redis >= 6.2 if you use Redis to store counters

Installation
------------

Add the gem to your `Gemfile`:

    gem 'rack-limits'

Or install it directly:

    $ gem install rack-limits

Examples
--------

### Adding throttling to a Rails application

    # config/application.rb
    require 'rack/limits'

    class Application < Rails::Application
      config.middleware.use Rack::Limits::Interval
    end

### Adding throttling to a Sinatra application

    require 'sinatra'
    require 'rack/limits'

    use Rack::Limits::Interval

    get('/hello') { "Hello, world!\n" }

### Adding throttling to a Rackup application

    # config.ru
    require 'rack/limits'

    use Rack::Limits::Interval

    run ->(env) { [200, { 'content-type' => 'text/plain' }, ["Hello, world!\n"]] }

### Enforcing a minimum 3-second interval between requests

    use Rack::Limits::Interval, min: 3.0

### Allowing a maximum of 100 requests per hour

    use Rack::Limits::Hourly,   max: 100

### Allowing a maximum of 1,000 requests per day

    use Rack::Limits::Daily,    max: 1000

### Combining various throttling constraints into one overall policy

    use Rack::Limits::Daily,    max: 1000  # requests
    use Rack::Limits::Hourly,   max: 100   # requests
    use Rack::Limits::Interval, min: 3.0   # seconds

### Storing the rate-limiting counters on a Redis server

    require 'redis'

    use Rack::Limits::Hourly, max: 100, cache: Redis.new, key_prefix: :limits

The `:cache` option also accepts a `Proc`, which is called on every request.
Use it to check out a connection from a pool:

    use Rack::Limits::Hourly, max: 100, key_prefix: :limits,
        cache: -> { Thread.current[:limits_redis] ||= Redis.new }

### Storing the rate-limiting counters on a Memcached server

    require 'dalli'

    use Rack::Limits::Hourly, max: 100, cache: Dalli::Client.new, key_prefix: :limits

### Storing the rate-limiting counters in a GDBM database

    require 'gdbm' # gem 'gdbm'

    use Rack::Limits::Interval, cache: GDBM.new('tmp/limits.db')

More runnable `config.ru` examples are in the [`etc/`](etc) directory.

Throttling Strategies
---------------------

`Rack::Limits` supports three built-in throttling strategies:

* `Rack::Limits::Interval`: Limits the application by enforcing a
  minimum interval (by default, 1 second) between subsequent HTTP requests.
  Every request, including a rejected one, restarts the interval.
* `Rack::Limits::Hourly`: Limits the application by defining a
  maximum number of allowed HTTP requests per hour (by default, 3,600
  requests per 60 minutes, which works out to an average of 1 request per
  second). Counters reset every hour on the hour.
* `Rack::Limits::Daily`: Limits the application by defining a
  maximum number of allowed HTTP requests per day (by default, 86,400
  requests per 24 hours, which works out to an average of 1 request per
  second). Counters reset at midnight.

Hourly and daily windows follow the server's local time zone.

You can customize any of these strategies by subclassing it. If your
requirements go beyond these strategies, you can write a new one by
subclassing `Rack::Limits::Limiter` directly.

HTTP Client Identification
--------------------------

The rate-limiting counters stored and maintained by `Rack::Limits` are
keyed to unique HTTP clients.

By default, HTTP clients are uniquely identified by their IP address as
returned by `Rack::Request#ip`. If you wish to instead use a more granular,
application-specific identifier such as a session key or a user account
name, you need only subclass a throttling strategy implementation and
override the `#client_identifier` method. You can also pass a `:key` proc
that receives the `Rack::Request` and returns the whole cache key.

HTTP Response Codes and Headers
-------------------------------

### 429 Too Many Requests

When a client exceeds a rate limit, `Rack::Limits` returns a
[`429 Too Many Requests`][RFC 6585] response with the message
"Rate Limit Exceeded" in a `text/plain` body:

    HTTP/1.1 429 Too Many Requests
    content-type: text/plain; charset=utf-8
    retry-after: 1800
    ratelimit-limit: 100
    ratelimit-remaining: 0
    ratelimit-reset: 1800

    429 Too Many Requests (Rate Limit Exceeded)

| Header                | Meaning                                                    |
| --------------------- | ---------------------------------------------------------- |
| `retry-after`         | Seconds the client should wait before retrying             |
| `ratelimit-limit`     | Requests allowed per window (`1` for `Interval`)           |
| `ratelimit-remaining` | Requests left in the current window (always `0` on a 429)  |
| `ratelimit-reset`     | Seconds until the current window resets                    |

The `RateLimit-*` headers use the names from the IETF
[RateLimit header fields draft][ratelimit-headers] that are widely used in
practice. Header names are lowercase, as Rack 3 requires.

Versions before 0.4.0 returned `403 Forbidden` by default. To get the old
status code or a different message, pass `:code` and `:message`:

    use Rack::Limits::Hourly, max: 100, code: 403, message: 'Slow down'

Concurrency and atomicity
-------------------------

Concurrent requests from the same client cannot get past a limit, because
each check-and-update of a counter is a single atomic operation:

| Store                         | Hourly / Daily                     | Interval                       | Atomic across processes? |
| ----------------------------- | ---------------------------------- | ------------------------------ | ------------------------ |
| Redis (>= 6.2)                | `INCR`, plus `EXPIRE` on creation  | `SET key value GET PX ttl`     | Yes                      |
| Memcached via Dalli           | `incr` with TTL and initial value  | in-process lock                | Hourly/Daily only        |
| `Hash`, `GDBM`, other stores  | in-process lock                    | in-process lock                | No                       |

The in-process lock makes updates atomic across threads (for example Puma
threads). It cannot coordinate separate processes (Puma workers, Unicorn,
several hosts). For those deployments, use Redis.

If the cache backend raises an error (for example, Redis is down), the
request is **allowed**, so an outage of the rate-limit store doesn't take
your application down with it.

Hourly and daily counters in Redis and Memcached expire on their own. A
`Hash` cache keeps old windows' keys until the process restarts.

Documentation
-------------

API documentation: <https://www.rubydoc.info/gems/rack-limits>

* {Rack::Limits}
  * {Rack::Limits::Interval}
  * {Rack::Limits::Daily}
  * {Rack::Limits::Hourly}

Development
-----------

    $ git clone https://github.com/nikoma/rack-limits.git
    $ cd rack-limits
    $ bundle install
    $ bundle exec rake                                   # run the specs
    $ REDIS_URL=redis://localhost:6379/15 bundle exec rake   # also run Redis integration specs

CI runs the specs on every supported Ruby and Rack version with GitHub
Actions.

Authors
-------

Original authors of rack-throttle, on which this project is based:

* [Arto Bendiken](mailto:arto.bendiken@gmail.com) - <https://ar.to/>
* [Brendon Murphy](mailto:disposable.20.xternal@spamourmet.com) - <http://www.techfreak.net/>

rack-limits fork maintained by:

* Nikolai Manek - <https://github.com/nikoma>

Contributors
------------

* [karmi](https://github.com/karmi) - Rack-compliant (Array) response body

License
-------

`Rack::Limits` is free and unencumbered public domain software. For more
information, see <https://unlicense.org/> or the accompanying UNLICENSE file.

[Rack]:              https://github.com/rack/rack
[rack-throttle]:     https://github.com/dryruby/rack-throttle
[redis]:             https://rubygems.org/gems/redis
[dalli]:             https://rubygems.org/gems/dalli
[gdbm]:              https://rubygems.org/gems/gdbm
[RFC 6585]:          https://www.rfc-editor.org/rfc/rfc6585#section-4
[ratelimit-headers]: https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/
