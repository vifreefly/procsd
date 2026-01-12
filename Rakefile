require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task :clear_coverage do
  rm_rf "coverage"
end

task :coverage_report do
  require "simplecov"
  SimpleCov.collate Dir["coverage/.resultset.json"] do
    coverage_dir "coverage"
    enable_coverage :branch
  end
end

task :default => [:clear_coverage, :test, :coverage_report]
