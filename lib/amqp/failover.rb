# encoding: utf-8

require 'amqp/failover_client'
require 'amqp/failover/config'
require 'amqp/failover/configurations'
require 'amqp/failover/logger'
require 'amqp/failover/server_discovery'
require 'amqp/failover/version'
require 'amqp/failover/ext/amqp/client.rb'


module AMQP
  class Failover
    
    attr_reader :latest_failed
    attr_accessor :primary
    attr_accessor :retry_timeout
    attr_accessor :fallback
    
    def initialize(confs = nil, opts = {})
      @configs = Failover::Configurations.new(confs)
      @options = default_options.merge(opts)
      @configs.primary_ref = @options[:primary_config]
    end
    
    class << self
      # pluggable logger specifically for tracking failover and fallbacks
      def logger
        @logger ||= Logger.new
      end
      attr_writer :logger
    end
    
    def default_options
      { :primary_config => 0,
        :retry_timeout => 1,
        :selection => :sequential, #TODO: Implement next server selection algorithm
        :fallback => false, #TODO: Enable by default once a sane implementation is figured out
        :fallback_interval => 10 }
    end
    
    def options
      @options ||= {}
    end
    
    def fallback_interval
      options[:fallback_interval] ||= default_options[:fallback_interval]
    end
    
    def primary
      configs[:primary]
    end
    
    def refs
      @refs ||= {}
    end
    
    def configs
      @configs ||= Configurations.new
    end
    
    def add_config(conf = {}, ref = nil)
      index = configs.index(conf)
      configs.set(conf) if index.nil?
      refs[ref] = (index || configs.index(conf)) if !ref.nil?
    end
    
    def failover_from(conf = {}, time = nil)
      failed_with(conf, nil, time)
      next_config
    end
    alias :from :failover_from
    
    def failed_with(conf = {}, ref = nil, time = nil)
      time ||= Time.now
      if !(index = configs.index(conf)).nil?
        configs[index].last_fail = time
        @latest_failed = configs[index]
      else
        @latest_failed = configs.set(conf)
        configs.last.last_fail = time
      end
      refs[ref] = (index || configs.index(conf)) if !ref.nil?
    end
    
    def next_config(retry_timeout = nil, after = nil)
      return nil if configs.size <= 1
      retry_timeout ||= @options[:retry_timeout]
      after ||= @latest_failed
      index = configs.index(after)
      available = (index > 0) ? configs[index+1..-1] + configs[0..index-1] : configs[1..-1]
      available.each do |conf|
        return conf if conf.last_fail.nil? || (conf.last_fail.to_i + retry_timeout) < Time.now.to_i
      end
      return nil
    end
    
    def last_fail_of(match)
      ((match.is_a?(Hash) ? get_by_conf(match) : get_by_ref(match)) || Config::Failed.new).last_fail
    end
    
    def get_by_conf(conf = {})
      configs[configs.index(conf)]
    end
    
    def get_by_ref(ref = nil)
      configs[refs[ref]] if refs[ref]
    end
    
  end # Failover
end # AMQP
