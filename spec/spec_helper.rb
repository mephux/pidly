gem 'rspec', '~> 2.4'
require 'rspec'

require 'pp'
require 'pidly'
include Pidly

class Test < Pidly::Control

  before_start do
    "BEFORE START #{@pid}"
  end

  start :when_daemon_starts

  stop do
    "Attempting to kill process: #{@pid}"
  end

  after_stop :test_after_daemon_stops
  
  error do
    "SENDING EMAIL | Error Count: #{@error_count}"
  end

  def when_daemon_starts
    loop do
      print "TEST FROM #{@pid}"
      sleep 2
    end
  end
  
  def test_after_daemon_stops
    puts "AFTER STOP"
  end

end

def test_callback(callback, defined=false)
  test = @daemon.fetch_class_var(callback.to_sym)
  
  if defined
    return true if test
    false
  else
    
    if test.kind_of?(Symbol)
      test
    elsif test.respond_to?(:call)
      test.call
    else
      nil
    end
    
  end
end