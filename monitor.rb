#!/usr/bin/env ruby
require 'docker'
require 'riemann/client'

SLEEP_INTERVAL = ENV.fetch('INTERVAL_TIME', '5').to_i
RIEMANN_ADDRESS = ENV.fetch('RIEMANN_ADDRESS')
RIEMANN_PORT = ENV.fetch('RIEMANN_PORT', '5555').to_i
c = Riemann::Client.new host: RIEMANN_ADDRESS, port: RIEMANN_PORT, timeout: 5

def log(container, c)
  begin
    container_json = container.json
  rescue StandardError
    puts 'Failed to get container json'
    return
  end
  return unless container_json

  env_vars = container_json['Config']['Env']
  marathon_env = env_vars.select { |env| env.start_with? 'MARATHON_APP_ID' }
  return unless marathon_env.any?

  marathon_id = marathon_env.first.split('=').last
  marathon_names = marathon_id.split('/').reject { |e| e == '' }.compact

  marathon_group = marathon_names.first if marathon_names.size > 1
  marathon_task = marathon_names.last

  host = env_vars.select { |e| e.start_with? 'HOST' }.first.split('=').last
  riemann_marathon_name = marathon_group.nil? ? marathon_task : "#{marathon_group}-#{marathon_task}"

  stats = Docker::Util.parse_json(container.connection.get("/containers/#{container.id}/stats", stream: false))

  memory_stats = stats['memory_stats']
  memory_usage = memory_stats['usage'].to_f
  memory_total = memory_stats['limit'].to_f
  memory_percentage = memory_usage / memory_total

  state = container_json['State']
  running = state['Running']
  if running
    start_time = DateTime.rfc3339(state['StartedAt']).to_time.utc.to_i
    now = DateTime.now.to_time.utc.to_i
    uptime = now - start_time

    c.tcp << {
      host: host,
      service: "docker #{riemann_marathon_name} uptime",
      metric: uptime
    }
  end

  c.tcp << {
    host: host,
    service: "docker #{riemann_marathon_name} mem usage",
    metric: memory_usage
  }

  c.tcp << {
    host: host,
    service: "docker #{riemann_marathon_name} mem total",
    metric: memory_total
  }

  c.tcp << {
    host: host,
    service: "docker #{riemann_marathon_name} net rx",
    metric: stats['network']['rx_bytes']
  }
  c.tcp << {
    host: host,
    service: "docker #{riemann_marathon_name} net tx",
    metric: stats['network']['tx_bytes']
  }

  c.tcp << {
    host: host,
    service: "docker #{riemann_marathon_name} mem ratio",
    metric: memory_percentage
  }
end

loop do
  containers = Docker::Container.all
  containers.each do |container|
    begin
      log(container, c)
    rescue StandardError => e
      puts "Cannot get status for #{container.id} #{e.message}"
    end
  end
  sleep SLEEP_INTERVAL
end
