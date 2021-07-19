# frozen_string_literal: true

require 'dotenv/load'
require 'bunny-pub-sub/subscriber'
require 'bunny-pub-sub/publisher'
require_relative 'overseer_receive_action.rb'

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

assessment_results_publisher = Publisher.new assessment_results_publisher_config

# Register subscriber for task submissions, runs overseer receive, and publishes results to assessment_results_publisher
register_subscriber(subscriber_config,
                    method(:receive),
                    assessment_results_publisher)
