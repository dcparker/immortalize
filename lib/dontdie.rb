#!/usr/bin/env ruby

# Usage:
#   dontdie run "command --with-args --etc"
#   dontdie remove "command --with-args --etc"
#   dontdie inspect
#   dontdie # << run this from a cron job every minute to check and restart failed processes. 
#   * starts process
#   * logs the start command with pid
#   * when run from cron (without args), check all logged start commands and currently logged pid to see if it's running
#     * if not running, immediately remove pid from log, but leave command; start process again via: dontdie "command --with-args --etc"
require 'time'
require 'yaml'
require 'sha1'

$log_location = "/var/log/dontdie"
`mkdir -p "#{$log_location}"` unless File.directory?($log_location)
$registry_filename = "#{$log_location}/registry.yaml"
File.open($registry_filename, 'w'){|f| f << {}.to_yaml} unless File.exists?($registry_filename)
$registry = YAML.load_file($registry_filename)

class Immortal
  attr_reader :identifier
  def initialize(identifier)
    @identifier = identifier
    @reg = $registry[identifier]
  end

  def command
    @reg[:command]
  end

  def running?
    @reg[:pid] && `ps #{@reg[:pid]} | grep "#{@reg[:pid]}"` =~ /#{@reg[:pid]}/
  end

  def failures
    @failures ||= File.exists?(failure_log_file) ? File.readlines(failure_log_file).map {|t| Time.parse(t) } : []
  end

  def start!
    # Run the command and gather the pid
    pid = nil
    open("|#{command} & echo $!") do |f|
      pid = f.sysread(5).chomp.to_i
    end
    # Log the pid
    puts "Pid: #{pid}"
    $registry[identifier][:pid] = pid
  end

  def failed!
    failures << Time.now
    File.open(failure_log_file, 'a') do |log|
      log << "#{Time.now}\n"
    end
  end

  def frequent_failures?
    # If it failed 5 times or more within the last hour.
    failures.length >= 5 && failures[-5] > Time.now - 1.hour
  end

  private
  def failure_log_file
    "#{$log_location}/#{@identifier}"
  end
end

# Main logic
unless ::Object.const_defined?(:IRB)
  case ARGV[0]
  when 'inspect'
    puts $registry.inspect
    exit

  when 'run'
    # Running with a given command.
    command_string = ARGV[1]
    identifier = SHA1.hexdigest(command_string)

    # Create the command
    puts $registry[identifier].inspect
    $registry[identifier] ||= {
      :command => command_string
    }

    immortal = Immortal.new(identifier)
    # Start the process if it isn't already running
    if immortal.running?
      puts "`#{immortal.command}' already running!"
    else
      puts "Starting `#{immortal.command}'..."
      immortal.start!
    end

  when 'remove'
    command_string = ARGV[1]
    identifier = SHA1.hexdigest(command_string)
    $registry.delete(identifier)

  when nil
    # Running bare from cron.
    # Check all logged commands with pids.
    $registry.each do |identifier,info|
      immortal = Immortal.new(identifier)
    
      # Check if running
      if immortal.running?
        puts "`#{immortal.command}' is running fine..."
      else
        puts "`#{immortal.command}' HAS DIED! Reviving..."
        # Mark the failure
        immortal.failed!
        # Start it
        immortal.start!
        # Notify if failures have been frequent
        puts "! FREQUENT FAILURE ON #{identifier} (`#{immortal.command}')" if immortal.frequent_failures?
      end
    end
  end
end

# Save the registry
File.open("#{$log_location}/registry.yaml", 'w') do |r|
  r << $registry.to_yaml
end

# Get ALL master merb pids:
#   ps auxw | grep 'merb' | grep -v 'grep' | grep "merb : merb : master" | awk '{print $2}'

# Get child processes of $PPID:
#   ps -o pid,ppid -ax | awk '{print $1,$2}' | grep " $PPID" | awk '{print $1}'


# This shows the last-started worker pid for this app
#   `cat log/merb.4000.pid`
