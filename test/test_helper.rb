require "simplecov"

SimpleCov.start do
  root File.expand_path("../..", __FILE__)
  coverage_dir "coverage"
  command_name "unit"
  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "procsd"

require "minitest/autorun"
