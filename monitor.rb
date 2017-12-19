require 'docker'

def task_name_for_marathon_container(env)
  marathon_env = env.select { |e| e.start_with? 'MARATHON_APP_ID' }
  return nil unless marathon_env.any?
  marathon_id = marathon_env.first.split('=').last
  marathon_names = marathon_id.split('/').reject { |e| e == '' }.compact

  marathon_group = marathon_names.first if marathon_names.size > 1
  marathon_task = marathon_names.last
  marathon_group.nil? ? marathon_task : "#{marathon_group}-#{marathon_task}"
end

def task_name_for_chronos_container(env)
  c = env.select { |e| e.start_with? 'CHRONOS_JOB_NAME' }
  return nil unless c.any?
  c.first.split('=').last
end

def can_generate_name_from_container?(env_vars)
  env_vars.select { |e|
    e.start_with?('MARATHON_APP_ID')|| e.start_with?('CHRONOS_JOB_NAME')
  }.any?
end

def task_name_from_container(env)
  return nil unless can_generate_name_from_container?(env)
  task_name_for_marathon_container(env) || task_name_for_chronos_container(env)
end

def stats_for_container(container, state)
  stats = Docker::Util.parse_json(container.connection.get("/containers/#{container.id}/stats", stream: false))
  memory_stats = stats['memory_stats']
  memory_usage = memory_stats['usage'].to_f
  memory_total = memory_stats['limit'].to_f
  memory_percentage = memory_usage / memory_total

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
    net_rx: stats.dig('network', 'rx_bytes'),
    net_tx: stats.dig('network', 'tx_bytes'),
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
  events.map { |e| e[:host] = host; e }
end

def host_from_env(env)
  host = env.select { |e| e.start_with? 'HOST' }
  return nil unless host.any?
  host.first.split('=').last
end

def riemann_events(container)
  begin
    container_json = container.json
  rescue StandardError
    puts 'Failed to get container json'
    return
  end

  return [] unless container_json

  env_vars = container_json['Config']['Env']
  state = container_json['State']
  host = host_from_env(env_vars)

  task = task_name_from_container(env_vars)
  return [] unless task

  stats = stats_for_container(container, state)
  stats_to_events(stats, task, host)
end
