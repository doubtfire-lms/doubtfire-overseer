#!/usr/local/bin/ruby

require "./receive_rabbit_mq.rb"

begin
  puts ENV['ROUTE_KEY'].nil?
  return puts "Must define environment variable ROUTE_KEY" if ENV['ROUTE_KEY'].nil?
  return puts "Must define environment variable LANGUAGE_ENVIRONMENTS" if ENV['LANGUAGE_ENVIRONMENTS'].nil?
  return puts "Must define environment variable DEFAULT_LANGUAGE_ENVIRONMENT" if ENV['DEFAULT_LANGUAGE_ENVIRONMENT'].nil?

  receiver = Receiver.new
  receiver.start
rescue RuntimeError => msg
  puts msg
end
