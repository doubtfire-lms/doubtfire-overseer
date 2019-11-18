# frozen_string_literal: true

require 'dotenv/load'
require 'bunny-pub-sub/subscriber'
require 'bunny-pub-sub/publisher'
require_relative 'overseer_receive_action.rb'

subscriber_config = {
  RABBITMQ_HOSTNAME: ENV['RABBITMQ_HOSTNAME'],
  RABBITMQ_USERNAME: ENV['RABBITMQ_USERNAME'],
  RABBITMQ_PASSWORD: ENV['RABBITMQ_PASSWORD'],
  EXCHANGE_NAME: ENV['EXCHANGE_NAME'],
  DURABLE_QUEUE_NAME: ENV['DURABLE_QUEUE_NAME'],
  BINDING_KEYS: ENV['BINDING_KEYS'],
  DEFAULT_BINDING_KEY: ENV['DEFAULT_BINDING_KEY']
}

assessment_results_publisher_config = {
  RABBITMQ_HOSTNAME: ENV['RABBITMQ_HOSTNAME'],
  RABBITMQ_USERNAME: ENV['RABBITMQ_USERNAME'],
  RABBITMQ_PASSWORD: ENV['RABBITMQ_PASSWORD'],
  EXCHANGE_NAME: ENV['EXCHANGE_NAME'],
  DURABLE_QUEUE_NAME: 'assessment_results',
  BINDING_KEYS: ENV['BINDING_KEYS'],
  DEFAULT_BINDING_KEY: ENV['DEFAULT_BINDING_KEY'],
  # Publisher specific key
  # Note: `*.result` works too, but it makes no sense using that.
  ROUTING_KEY: 'assessment.result'
}

assessment_results_publisher = Publisher.new assessment_results_publisher_config

register_subscriber(subscriber_config,
                    method(:receive),
                    assessment_results_publisher)
