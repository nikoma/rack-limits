# Changelog

## 0.4.0 (unreleased)

### Breaking changes

* Throttled requests now get **`429 Too Many Requests`** instead of `403 Forbidden`.
  Pass `code: 403` to keep the old behaviour.
* Requires Ruby >= 3.2 and Rack >= 3.0, < 4.
* Response header names are lowercase, as Rack 3 requires
  (`content-type`, `retry-after`).
* Removed the `VERSION` file; the version lives in `Rack::Limits::VERSION`.

### Added

* `Retry-After` on throttled responses from `Hourly` and `Daily` (previously
  only `Interval`), plus `RateLimit-Limit`, `RateLimit-Remaining` and
  `RateLimit-Reset` headers.
* Counter updates are atomic: Redis `INCR`/`SET … GET`, Dalli `incr`, and an
  in-process lock for other stores. Concurrent requests can no longer get past
  a limit.
* Hourly and daily counters in Redis and Memcached expire automatically.
* Gemspec, Bundler setup, RSpec 3 suite (with Rack::Lint, concurrency and
  Redis integration specs) and GitHub Actions CI.

### Fixed

* `require 'rack/limits'` failed because the library files lived under
  `lib/rack/throttle/`.
* `Rack::Limits::Daily#max_per_day` memoized into `@max_per_hour`.
* Limiters no longer mutate the options hash passed to them.

### Documentation

* Rewrote the README for current Ruby, Rack, Redis and Dalli; replaced dead
  rubyforge, Heroku and `git://` links.

## 0.3.0

* Forked from [rack-throttle](https://github.com/dryruby/rack-throttle) as `Rack::Limits`.
