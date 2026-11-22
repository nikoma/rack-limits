# frozen_string_literal: true

module Rack; module Limits
  module VERSION
    MAJOR = 0
    MINOR = 4
    TINY  = 0
    EXTRA = nil

    STRING = [MAJOR, MINOR, TINY, EXTRA].compact.join('.').freeze

    ##
    # @return [String]
    def self.to_s() STRING end

    ##
    # @return [String]
    def self.to_str() STRING end

    ##
    # @return [Array(Integer, Integer, Integer)]
    def self.to_a() [MAJOR, MINOR, TINY] end
  end
end; end
