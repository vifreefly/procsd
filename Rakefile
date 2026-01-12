require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "cucumber/rake/task"

RSpec::Core::RakeTask.new(:spec)

Cucumber::Rake::Task.new(:cucumber) do |t|
  t.cucumber_opts = ["--format", "progress"]
end

task :clear_coverage do
  rm_rf "coverage"
end

task :coverage_report do
  require "simplecov"
  SimpleCov.collate Dir["coverage/.resultset*.json"] do
    coverage_dir "coverage"
    enable_coverage :branch
  end
end

task test: [:spec, :cucumber]
task default: [:clear_coverage, :test, :coverage_report]
