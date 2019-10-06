require "bunny"
require "json"
require "zip"
require "pathname"

class ClientException < RuntimeError
  attr_reader :status

  def initialize(status = 400, message)
    puts "Client error: #{message.to_s}, #{status}"
    @status = status
    super(message)
  end
end

class ServerException < RuntimeError
  attr_reader :status

  def initialize(status = 500, message)
    puts "Server error: #{message.to_s}, #{status}"
    @status = status
    super(message)
  end
end

def client_error!(message, status, _headers = {}, _backtrace = [])
  raise ClientException.new status, message
end

def server_error!(message, status, _headers = {}, _backtrace = [])
  raise ServerException.new status, message
end

class Receiver

  ##################################################################
  ##################################################################

  def start
    puts ENV['RABBITMQ_HOSTNAME']
    # return
    connection = Bunny.new(hostname: ENV['RABBITMQ_HOSTNAME'] || 'localhost', username: "guest", password: "guest")
    connection.start

    channel = connection.create_channel
    exchange = channel.topic('asssessment', :durable => true)
    #channel.prefetch(1) # Use this for making rabbitMQ not give a worker more than 1 jobs if it is already working on one.

    queue = channel.queue(ENV['ROUTE_KEY'], durable: true)
    

    language_environments = ENV['LANGUAGE_ENVIRONMENTS'].split(',')
    language_environments.each do |language_environment| # language_environments can be something like "#.csharp" "#.splashkit.csharp" "#.python", etc.
      queue.bind(exchange, routing_key: language_environment)
    end
    queue.bind(exchange, routing_key: ENV['DEFAULT_LANGUAGE_ENVIRONMENT']) unless ENV['DEFAULT_LANGUAGE_ENVIRONMENT'].nil?

    begin
      puts " [*] Waiting for messages. To exit press CTRL+C"
      queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, params|
        params = JSON.parse(params)

        puts params
        channel.ack(delivery_info.delivery_tag)
      end
    rescue Interrupt => _
      connection.close

      exit(0)
    end # Outer begin
  end
end
