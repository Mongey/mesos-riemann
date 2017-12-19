require 'minitest/autorun'
require 'minitest/reporters'
require 'docker-api'
require_relative '../monitor.rb'

reporter_options = { color: true }
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(reporter_options)]
