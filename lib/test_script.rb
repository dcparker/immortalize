#!/usr/bin/env ruby

trap('TERM') do
  puts "Force exit"
  exit
end

puts "I am process #{Process.pid}"
sleep 30
puts "Exiting"
`touch exited`
