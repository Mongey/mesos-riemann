#!/usr/bin/env ruby

require_relative 'monitor.rb'
require 'docker'
require 'riemann/client'

SLEEP_INTERVAL = ENV.fetch('INTERVAL_TIME', '5').to_i
RIEMANN_ADDRESS = ENV.fetch('RIEMANN_ADDRESS')
RIEMANN_PORT = ENV.fetch('RIEMANN_PORT', '5555').to_i

c = Riemann::Client.new host: RIEMANN_ADDRESS, port: RIEMANN_PORT, timeout: 5

loop do
  containers = Docker::Container.all
  containers.each do |container|
    c.tcp << riemann_events(container)
  end
  sleep SLEEP_INTERVAL
end
