require 'fileutils'
require 'pathname'

require 'pidly/callbacks'
require 'pidly/logger'

module Pidly

  #
  # Pidly Master Control
  #
  class Control

    # Include callbacks
    include Pidly::Callbacks
    include Pidly::Logger

    attr_accessor :daemon, :name, :pid_file,
      :log_file, :path, :sync_log, :allow_multiple,
      :verbose, :pid, :timeout, :error_count, :messages

    #
    # Initialize Control Object
    #
    #
    def initialize(options={})

      @messages = []

      @error_count = 0

      @name = options.fetch(:name)

      if options.has_key?(:path)
        @path = Pathname.new(options.fetch(:path))
      else
        @path = Pathname.new('/tmp')
      end

      unless @path.directory?
        raise('Path does not exist or is not a directory.')
      end

      unless @path.readable? && @path.writable?
        raise('Path must be readable and writable.')
      end

      if options.has_key?(:pid_file)
        @pid_file = options.fetch(:pid_path)
      else
        @pid_file = File.join(@path.to_s, 'pids', @name + '.pid')
      end

      if options.has_key?(:log_file)
        @log_file = options.fetch(:log_path)
      else
        @log_file = File.join(@path.to_s, 'logs', @name + '.log')
      end

      @pid = fetch_pid if File.file?(@pid_file)

      @sync_log = options.fetch(:sync_log, true)

      @allow_multiple = options.fetch(:allow_multiple, false)

      @signal = options.fetch(:signal, "TERM")

      @timeout = options.fetch(:timeout, 10)

      @verbosity = options.fetch(:verbose, false)
    end

    #
    # Spawn
    #
    # @param [Hash] options
    #   Configuration options for control object
    #
    # @return [Control] Control object
    #
    def self.spawn(options={})
      @daemon = new(options)
    end

    def start
      validate_files_and_paths!
      validate_callbacks!

      unless @allow_multiple
        if running?
          say :error, "An instance of #{@name} is already " +
            "running (PID #{@pid})"
          return
        end
      end

      @pid = fork do
        begin
          Process.setsid

          open(@pid_file, 'w') do |f|
            f << Process.pid
            @pid = Process.pid
          end

          execute_callback(:before_start)

          Dir.chdir @path.to_s
          File.umask 0000

          log = File.new(@log_file, "a")
          log.sync = @sync_log

          STDIN.reopen "/dev/null"
          STDOUT.reopen log
          STDERR.reopen STDOUT

          trap("TERM") do
            stop
          end

          execute_callback(:start)

        rescue RuntimeError => message
          STDERR.puts message
          STDERR.puts message.backtrace

          execute_callback(:error)
        rescue => message
          STDERR.puts message
          STDERR.puts message.backtrace

          execute_callback(:error)
        end
      end

    rescue => message
      STDERR.puts message
      STDERR.puts message.backtrace
      execute_callback(:error)
    end

    def stop

      if running?

        Process.kill(@signal, @pid)
        FileUtils.rm(@pid_file)

        execute_callback(:stop)

        begin
          Process.wait(@pid)
        rescue Errno::ECHILD
        end

        @timeout.downto(0) do
          sleep 1
          exit unless running?
        end

        Process.kill 9, @pid if running?
        execute_callback(:after_stop)

      else
        FileUtils.rm(@pid_file) if File.exists?(@pid_file)
        say :info, "PID file not found. Is the daemon started?"
      end

    rescue Errno::ENOENT
    end

    def status
      if running?
        say :info, "#{@name} is running (PID #{@pid})"
      else
        say :info, "#{@name} is NOT running"
      end
    end

    def restart
      stop; sleep 1 while running?; start
    end

    def kill(remove_pid_file=true)
      if running?
        say :info, "Killing #{@name} (PID #{@pid})"
        Process.kill 9, @pid
      end

      FileUtils.rm(@pid_file) if remove_pid_file
    rescue Errno::ENOENT
    end

    def running?
      Process.kill 0, @pid
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    rescue
      false
    end

    def validate_files_and_paths!
      log = Pathname.new(@log_file).dirname
      pid = Pathname.new(@pid_file).dirname

      unless File.directory?(log)
        FileUtils.mkdir_p(log.to_s)
      end

      unless File.directory?(pid)
        FileUtils.mkdir_p(pid.to_s)
      end
    end

    def validate_callbacks!
      unless Control.class_variable_defined?(:"@@start")
        raise('You must define a "start" callback.')
      end
    end

    def execute_callback(callback_name)
      @error_count += 1 if callback_name == :error

      if Control.class_variable_defined?(:"@@#{callback_name}")
        callback = Control.class_variable_get(:"@@#{callback_name}")

        if callback.kind_of?(Symbol)

          unless self.respond_to?(callback.to_sym)
            raise("Undefined callback method: #{callback}")
          end

          self.send(callback.to_sym)

        elsif callback.respond_to?(:call)

          self.instance_eval(&callback)

        else
          nil
        end

      end
      
    end

    def fetch_pid
      IO.read(@pid_file).to_i
    rescue
      nil
    end

    private :validate_callbacks!, :fetch_pid,
      :validate_files_and_paths!, :execute_callback

  end # class Control

end # module Pidly
