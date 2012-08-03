require 'rack'

module Rack
  module Limits
    autoload :Limiter,    'rack/limits/limiter'
    autoload :Interval,   'rack/limits/interval'
    autoload :TimeWindow, 'rack/limits/time_window'
    autoload :Daily,      'rack/limits/daily'
    autoload :Hourly,     'rack/limits/hourly'
    autoload :VERSION,    'rack/limits/version'
  end
end
