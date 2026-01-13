Given("a procsd.yml with:") do |content|
  @container.write_file("/home/testuser/myapp/procsd.yml", content)
end

Given("a Procfile with:") do |content|
  @container.write_file("/home/testuser/myapp/Procfile", content)
end

When("I wait {int} seconds") do |seconds|
  sleep(seconds)
end

When("I run {string}") do |command|
  @result = @container.exec(
    "#{ContainerHelper::CONTAINER_GEM_SRC}/bin/coverage #{command}",
    env: {
      "COVERAGE_ROOT" => ContainerHelper::CONTAINER_GEM_SRC,
      "COVERAGE_DIR" => ContainerHelper::CONTAINER_COVERAGE_DIR
    }
  )
end

def procsd_output
  @result.output.strip
end

Then("the command should succeed") do
  expect(@result).to be_success, "Command failed: #{@result.output}"
end

Then("the command should succeed with:") do |expected|
  expect(@result).to be_success, "Command failed: #{@result.output}"
  expect(procsd_output).to eq(expected.strip)
end

Then("the command should fail with:") do |expected|
  expect(@result).not_to be_success, "Command succeeded unexpectedly: #{@result.output}"
  expect(procsd_output).to eq(expected.strip)
end

Then("the output should match patterns:") do |patterns|
  output_lines = procsd_output.lines.map(&:chomp)
  pattern_lines = patterns.strip.lines.map(&:strip)

  expect(output_lines.size).to eq(pattern_lines.size),
    "Expected #{pattern_lines.size} lines, got #{output_lines.size}:\n#{procsd_output}"

  pattern_lines.each_with_index do |pattern, i|
    regex = Regexp.new("^#{pattern}$")
    expect(output_lines[i]).to match(regex),
      "Line #{i + 1}: expected to match #{regex.inspect}, got #{output_lines[i].inspect}"
  end
end

Then("the systemd directory should contain {string}") do |filename|
  files = @container.list_service_files("*")
  expect(files).to include(filename)
end

Then("the target {string} should be enabled") do |target_name|
  expect(@container.service_enabled?(target_name)).to be true
end

Then("the target {string} should be active") do |target_name|
  expect(@container.service_active?(target_name)).to be true
end

Then("the service {string} should be enabled") do |service_name|
  expect(@container.service_enabled?(service_name)).to be true
end

Then("the service {string} should be active") do |service_name|
  expect(@container.service_active?(service_name)).to be true
end

Then("the target {string} should not be active") do |target_name|
  expect(@container.service_active?(target_name)).to be false
end

Then("the service {string} should not be active") do |service_name|
  expect(@container.service_active?(service_name)).to be false
end

Then("the target {string} should not be enabled") do |target_name|
  expect(@container.service_enabled?(target_name)).to be false
end

Then("the systemd directory should not contain {string}") do |filename|
  files = @container.list_service_files("*")
  expect(files).not_to include(filename)
end

Then("the file {string} should contain:") do |path, content|
  actual = @container.read_file(path)
  expect(actual).to eq(content)
end

Then("the file {string} should exist") do |path|
  expect(@container.file_exists?(path)).to be true
end
