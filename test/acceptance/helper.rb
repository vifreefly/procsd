$LOAD_PATH.unshift File.expand_path("../../../lib", __FILE__)

require "minitest/autorun"
require "open3"
require "securerandom"
require "fileutils"

module Helper
  # minitest hooks
  def setup
    setup_container
  end

  def teardown
    teardown_container
  end

  DOCKERFILE_PATH = File.expand_path("Dockerfile", __dir__)
  IMAGE_NAME = "procsd-test"
  GEM_ROOT = File.expand_path("../..", __dir__)
  GEM_BUILD_DIR = "/tmp/procsd-test-gems"

  class Container
    attr_reader :id, :name

    def initialize
      @name = "procsd-test-#{SecureRandom.hex(4)}"
      @id = nil
    end

    def start
      ensure_image_built
      cmd = [
        "podman", "run", "-d",
        "--name", @name,
        "--hostname", "procsd-test",
        "--privileged",
        "--cgroupns=host",
        "-v", "/sys/fs/cgroup:/sys/fs/cgroup:rw",
        "-v", "#{GEM_BUILD_DIR}:/gem:ro",
        IMAGE_NAME
      ]

      output, status = Open3.capture2(*cmd)
      raise "Failed to start container: #{output}" unless status.success?

      @id = output.strip
      wait_for_systemd
      install_gem
      self
    end

    def stop
      return unless @id
      system("podman", "stop", "-t", "1", @name, out: File::NULL, err: File::NULL)
      system("podman", "rm", "-f", @name, out: File::NULL, err: File::NULL)
      @id = nil
    end

    def exec(command, user: "testuser", dir: "/home/testuser/myapp")
      full_cmd = ["podman", "exec", "-e", "USER=#{user}", "-u", user, "-w", dir, @name, "bash", "-lc", command]
      stdout, stderr, status = Open3.capture3(*full_cmd)
      Result.new(stdout, stderr, status.exitstatus)
    end

    def exec_as_root(command, raise_on_error: true)
      result = exec(command, user: "root", dir: "/")
      if raise_on_error && !result.success?
        raise "Command failed: #{command}\n#{result.output}"
      end
      result
    end

    def write_file(path, content, user: "testuser")
      copy_content_to_container(path, content)
      exec_as_root("chown #{user}:#{user} #{path}")
    end

    def read_file(path)
      result = exec_as_root("cat #{path}", raise_on_error: false)
      result.success? ? result.stdout : nil
    end

    def file_exists?(path)
      exec_as_root("test -f #{path}", raise_on_error: false).success?
    end

    def service_active?(service_name)
      exec_as_root("systemctl is-active --quiet #{service_name}", raise_on_error: false).success?
    end

    def service_enabled?(service_name)
      exec_as_root("systemctl is-enabled --quiet #{service_name}", raise_on_error: false).success?
    end

    def list_service_files(pattern)
      result = exec_as_root("ls -1 /etc/systemd/system/#{pattern} 2>/dev/null", raise_on_error: false)
      return [] unless result.success?
      result.stdout.strip.split("\n").map { |f| File.basename(f) }.reject(&:empty?)
    end

    private

    def install_gem
      exec_as_root("gem install /gem/procsd-test.gem --local --ignore-dependencies --no-document")
    end

    def copy_content_to_container(path, content)
      temp = "/tmp/procsd-#{SecureRandom.hex(4)}"
      File.write(temp, content)
      system("podman", "cp", temp, "#{@name}:#{path}", out: File::NULL)
      FileUtils.rm(temp)
    end

    def ensure_image_built
      build_image unless image_exists?
    end

    def image_exists?
      system("podman", "image", "exists", IMAGE_NAME, out: File::NULL, err: File::NULL)
    end

    def build_image
      build_gem
      cmd = ["podman", "build", "-t", IMAGE_NAME, "-f", DOCKERFILE_PATH, File.dirname(DOCKERFILE_PATH)]
      output, status = Open3.capture2e(*cmd)
      raise "Failed to build image: #{output}" unless status.success?
    end

    def build_gem
      FileUtils.mkdir_p(GEM_BUILD_DIR)
      gem_path = File.join(GEM_BUILD_DIR, "procsd-test.gem")
      Dir.chdir(GEM_ROOT) do
        system("gem", "build", "procsd.gemspec", "-o", gem_path, out: File::NULL, err: File::NULL)
      end
    end

    def wait_for_systemd(timeout: 30)
      start_time = Time.now
      loop do
        result = exec_as_root("systemctl is-system-running 2>/dev/null", raise_on_error: false)
        state = result.stdout.strip
        return if %w[running degraded].include?(state)

        if Time.now - start_time > timeout
          raise "Timeout waiting for systemd to be ready (state: #{state})"
        end

        sleep 0.5
      end
    end
  end

  class Result
    attr_reader :stdout, :stderr, :exit_status

    def initialize(stdout, stderr, exit_status)
      @stdout = stdout
      @stderr = stderr
      @exit_status = exit_status
    end

    def success?
      @exit_status == 0
    end

    def output
      @stdout + @stderr
    end
  end

  def setup_container
    @container = Container.new
    @container.start
  end

  def teardown_container
    @container&.stop
  end

  def container
    @container
  end

  def create_procsd_yml(content)
    container.write_file("/home/testuser/myapp/procsd.yml", content)
  end

  def create_procfile(content)
    container.write_file("/home/testuser/myapp/Procfile", content)
  end

  def run_procsd(command)
    container.exec("procsd #{command}")
  end
end
