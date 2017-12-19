require_relative 'test_helper'

class MonitorTest < Minitest::Test
  def test_marathon_env
    env =  ['HOST=mesos-agent-123',
            'MARATHON_APP_ID=myapp/web']

    assert task_name_from_container(env) == 'myapp-web'
    assert task_name_for_marathon_container([]).nil?
  end

  def test_chronos_env
    env =  ['HOST=mesos-agent-123',
            'CHRONOS_JOB_NAME=my-etl']

    assert task_name_from_container(env) == 'my-etl'

    assert task_name_for_chronos_container([]).nil?
  end

  def test_riemman_events
    task_name = 'foobar'
    image = Docker::Image.create('fromImage' => 'alpine:latest')
    container = Docker::Container.create('Cmd' => ['ls'],
                                         'Image' => 'alpine',
                                         'ENV' => ["HOST=localhost",
                                                   "CHRONOS_JOB_NAME=#{task_name}"])
    events = riemann_events(container)
    assert_equal [
      "docker #{task_name} mem usage",
      "docker #{task_name} mem total",
      "docker #{task_name} mem ratio",
      "docker #{task_name} net rx",
      "docker #{task_name} net tx",
    ], events.map{|e| e[:service]}

    assert_equal "localhost", events.map{|e| e[:host]}.first
  end
end
