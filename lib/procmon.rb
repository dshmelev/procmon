require "procmon/version"
require 'logger'

module Logging
  def logger
    @logger ||= Logging.logger_for(self.class.name)
  end

  # Use a hash class-ivar to cache a unique Logger per class:
  @loggers = {}

  class << self
    def logger_for(classname)
      @loggers[classname] ||= configure_logger_for(classname)
    end

    def configure_logger_for(classname)
      logger = Logger.new(STDOUT)
#      logger.level = Logger::WARN
      logger.progname = classname
      logger
    end
  end
end

module Procmon
  class App
    include Logging
    attr_reader :pid

    def initialize(&command)
      @command = command
    end

    def start
      return false if !self.valid?
      @pid = Process.fork do
        @command.call
      end
      Process.detach(@pid)
      logger.info "Start #{self.class} #{@pid}"
    end

    def stop
      logger.info "Stop #{self.class} #{@pid}"
      Process.kill "TERM",@pid
      Process.wait @pid rescue 0
    end

    def restart
      stop
      start {@command}
    end

    def valid?
      if run?
        logger.error "Already running..."
        return false
      end
      if !@command.instance_of? Proc
        logger.error "Job is not set. Closing..."
        return false
      end
      return true
    end

    def run?
      begin
        Process.getpgid( @pid )
        true
      rescue
        false
      end
    end

  end

  class Observer
    include Logging

    def initialize(params = {})
      @checkers = params.fetch(:checkers, []) # Checkers. Default empty array
      @apps     = params.fetch(:apps,     []) # Apps. Default empty array
    end

    def run
      return false if !self.valid?
      @apps.each do |app|
        app.start
      end
      while 1 do
        @apps.delete_if do |app|
          if !app.run?
            logger.warn "Delete stopped apps. PID: #{app.pid}"
            true
          end
        end
        break if !self.valid?
        @apps.each do |app|
          self.check_app(app)
        end
        sleep 1
      end
    end

    def valid?
      begin
        @checkers.each do |checker|
          checker.class.method_defined?("get")
        end
      rescue
        logger.error "Checkers is not valid"
        return false
      end

      begin
        @apps.each do |app|
          if !app.instance_of? Procmon::App
            raise "Apps is not Procmon::App class"
          end
        end
      rescue
        logger.error "Apps is not valid"
        return false
      end

      if @apps.empty?
        logger.error "Apps is empty"
        return false
      end
      if @checkers.empty?
        logger.error "Checkers is empty"
        return false
      end
      return true
    end

    def check_app(app)
      @checkers.each do |checker|
        pid = app.pid
        value   = checker.get(pid)
        trigger = checker.trigger
        logger.debug "#{pid} #{checker.class} #{value} #{trigger}"
        if value > trigger
          logger.warn "High load! Restart app #{pid}"
          app.restart
          return
        end
      end
    end

    def addapp(app)
      @apps << app
    end

    def addchk(checker)
      @checkers << checker
    end

    def delchk(checker)
      @checkers.delete(checker)
    end

  end

  class DataSource
    attr_reader :trigger

    def initialize(params = {})
      @trigger = params.fetch(:trigger, nil) # Trigger high value. Default nil
      @timeline = Timeline.new(5)
    end

    def stat
      stats = {}
      # Parsed items
      stats[:pid], stats[:comm], stats[:state], stats[:ppid], stats[:pgrp],
      stats[:session], stats[:tty_nr], stats[:tpgid], stats[:flags],
      stats[:minflt], stats[:cminflt], stats[:majflt], stats[:cmajflt],
      stats[:utime], stats[:stime], stats[:cutime], stats[:cstime],
      stats[:priority], stats[:nice], _, stats[:itrealvalue],
      stats[:starttime], stats[:vsize], stats[:rss], stats[:rlim],
      stats[:startcode], stats[:endcode], stats[:startstack], stats[:kstkesp],
      stats[:kstkeip], stats[:signal], stats[:blocked], stats[:sigignore],
      stats[:sigcatch], stats[:wchan], stats[:nswap], stats[:cnswap],
      stats[:exit_signal], stats[:processor], stats[:rt_priority],
      stats[:policy] = File.read("/proc/#{@pid}/stat").scan(/\(.*?\)|\w+/)
      # Calculated items
      stats[:cputime] = stats[:utime].to_i + stats[:stime].to_i # in jiffies
      stats
    end
  end

  class CpuMon < DataSource
    def get(pid)
      @pid = pid
      refresh = 1 * 1000 # in ms
      cpu_time = stat[:cputime] * 10 # in ms
      @timeline.push(cpu_time)
      return 0 if @timeline[-2].nil?
      ( ( @timeline[-1] -  @timeline[-2] ) * 100 / refresh ) # to percent
    rescue # This shouldn't fail is there's an error (or proc doesn't exist)
      0
    end
  end

  class MemMon < DataSource
    def get(pid)
      @pid = pid
      stat[:rss].to_i * 4 # in bytes
    rescue # This shouldn't fail is there's an error (or proc doesn't exist)
      0
    end
  end

  class Timeline < Array
    def initialize(max_size)
      super()
      @max_size = max_size
    end
    def push(val)
      self.concat([val])
      shift if size > @max_size
    end
    alias_method :<<, :push
  end
end
