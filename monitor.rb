#!/usr/bin/env ruby
require 'docker'
require 'riemann/client'

SLEEP_INTERVAL = ENV.fetch('INTERVAL_TIME', '5').to_i
RIEMANN_ADDRESS = ENV.fetch('RIEMANN_ADDRESS')
RIEMANN_PORT = ENV.fetch('RIEMANN_PORT', '5555').to_i
c = Riemann::Client.new host: RIEMANN_ADDRESS, port: RIEMANN_PORT, timeout: 5

def task_name_from_container(env_vars)
  marathon_env = env_vars.select { |env| env.start_with? 'MARATHON_APP_ID' }
  return unless marathon_env.any?

  marathon_id = marathon_env.first.split('=').last
  marathon_names = marathon_id.split('/').reject { |e| e == '' }.compact

  marathon_group = marathon_names.first if marathon_names.size > 1
  marathon_task = marathon_names.last
  marathon_group.nil? ? marathon_task : "#{marathon_group}-#{marathon_task}"
end

def stats_for_container(container_id)
  stats = Docker::Util.parse_json(container.connection.get("/containers/#{container_id}/stats", stream: false))
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
  end

  {
    running: running,
    uptime: uptime,
    memory_usage: memory_usage,
    memory_total: memory_total,
    memory_percentage: memory_percentage,
    net_rx: stats['network']['rx_bytes'],
    net_tx: stats['network']['tx_bytes'],
  }
end

def stats_to_events(stats, name, host)
  prefix = "docker #{name}"
  events = [
    {
      service: "#{prefix} mem usage",
      metric: stats[:memory_usage]
    },
    {
      service: "#{prefix} mem total",
      metric: stats[:memory_total]
    },
    {
      service: "#{prefix} mem ratio",
      metric: stats[:memory_percentage]
    },
    {
      service: "#{prefix} net rx",
      metric: stats[:net_rx]
    },
    {
      service: "#{prefix} net tx",
      metric: stats[:net_tx]
    }
  ]

  if stats[:running]
    events << {
      service: "#{prefix} uptime",
      metric: stats[:uptime]
    }
  end
  events.map {|e| e[:host] = host; e}
end

def log(container, c)
  begin
    container_json = container.json
  rescue StandardError
    puts 'Failed to get container json'
    return
  end
  return unless container_json

  env_vars = container_json['Config']['Env']
  riemann_marathon_name = task_name_from_container(env_vars)
  return unless riemann_marathon_name

  host = env_vars.select { |e| e.start_with? 'HOST' }.first.split('=').last
  stats = stats_for_container(container.id)
  c.tcp << stats_to_events(stats, riemann_marathon_name, host)
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
