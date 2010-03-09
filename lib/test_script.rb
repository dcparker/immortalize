#!/usr/bin/env ruby

trap('TERM') do
  puts "Force exit"
  exit
end

puts "I am process #{Process.pid}"
# sleep 1
puts "Exiting"
