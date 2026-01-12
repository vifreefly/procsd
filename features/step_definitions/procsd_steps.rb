Given("a procsd.yml with:") do |content|
  @container.write_file("/home/testuser/myapp/procsd.yml", content)
end

Given("a Procfile with:") do |content|
  @container.write_file("/home/testuser/myapp/Procfile", content)
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

Then("the command should succeed") do
  expect(@result).to be_success, "Command failed: #{@result.output}"
end

Then("the command should fail") do
  expect(@result).not_to be_success
end

Then("the output should contain {string}") do |text|
  expect(@result.output).to include(text)
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

Then("the file {string} should contain:") do |path, content|
  actual = @container.read_file(path)
  expect(actual).to eq(content)
end

Then("the file {string} should exist") do |path|
  expect(@container.file_exists?(path)).to be true
end
