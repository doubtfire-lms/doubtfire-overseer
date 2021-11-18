# frozen_string_literal: true

require 'dotenv/load'
require 'bunny-pub-sub/subscriber'
require 'bunny-pub-sub/publisher'
require_relative 'overseer_receive_action.rb'

docker_config = {
  DOCKER_PROXY_URL: ENV['DOCKER_PROXY_URL'],
  DOCKER_TOKEN: ENV['DOCKER_TOKEN'],
  DOCKER_USER: ENV['DOCKER_USER']
}
subscriber_config = {
  RABBITMQ_HOSTNAME: ENV['RABBITMQ_HOSTNAME'],
  RABBITMQ_USERNAME: ENV['RABBITMQ_USERNAME'],
  RABBITMQ_PASSWORD: ENV['RABBITMQ_PASSWORD'],
  EXCHANGE_NAME: 'ontrack',
  DURABLE_QUEUE_NAME: 'q.tasks',
  BINDING_KEYS: 'task.submission',
  DEFAULT_BINDING_KEY: 'task.submission'
}

assessment_results_publisher_config = {
  RABBITMQ_HOSTNAME: ENV['RABBITMQ_HOSTNAME'],
  RABBITMQ_USERNAME: ENV['RABBITMQ_USERNAME'],
  RABBITMQ_PASSWORD: ENV['RABBITMQ_PASSWORD'],
  EXCHANGE_NAME: 'ontrack',
  DURABLE_QUEUE_NAME: 'q.overseer',
  # Publisher specific key
  # Note: `*.result` works too, but it makes no sense using that.
  ROUTING_KEY: 'overseer.result'
}

if docker_config[:DOCKER_TOKEN] && docker_config[:DOCKER_PROXY_URL]
  puts "Logging into docker proxy"
  `echo \"${DOCKER_TOKEN}\" | docker login --username ${DOCKER_USER} --password-stdin ${DOCKER_PROXY_URL}`
end

assessment_results_publisher = Publisher.new assessment_results_publisher_config

# Register subscriber for task submissions, runs overseer receive, and publishes results to assessment_results_publisher
register_subscriber(subscriber_config,
                    method(:receive),
                    assessment_results_publisher)
