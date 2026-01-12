require "yaml"
require "erb"

module Procsd
  class Config
    class Error < StandardError; end

    attr_reader :app, :processes, :environment, :dev_environment, :systemd_dir, :nginx

    def self.load(path = "procsd.yml")
      new(path)
    end

    def initialize(path)
      raise Error, "Config file #{path} doesn't exists" unless File.exist?(path)

      procsd = parse_yaml(path)

      raise Error, "Missing app name in the procsd.yml file" unless procsd["app"]
      @app = procsd["app"]

      @processes = load_processes(procsd)
      @environment = procsd["environment"] || {}
      @dev_environment = procsd["dev_environment"] || {}
      @systemd_dir = procsd["systemd_dir"] || Procsd::DEFAULT_SYSTEMD_DIR
      @nginx = procsd["nginx"]
    end

    def to_h
      {
        app: @app,
        processes: @processes,
        environment: @environment,
        dev_environment: @dev_environment,
        systemd_dir: @systemd_dir,
        nginx: @nginx
      }
    end

    private

    def parse_yaml(path)
      YAML.safe_load(ERB.new(File.read(path)).result)
    rescue => e
      raise Error, "Can't read #{path}: #{e.inspect}"
    end

    def load_processes(procsd)
      processes_data = procsd["processes"] || load_procfile
      formation = parse_formation(procsd["formation"])

      processes = {}
      processes_data.each do |name, opts|
        if opts.is_a?(Hash)
          raise Error, "Missing ExecStart command for `#{name}` process" unless opts["ExecStart"]
          processes[name] = { "commands" => opts }
        else
          processes[name] = { "commands" => { "ExecStart" => opts } }
        end
        processes[name]["size"] = formation[name] || 1
      end
      processes
    end

    def load_procfile
      raise Error, "Procfile doesn't exists. Define processes in procsd.yml or create Procfile" unless File.exist?("Procfile")
      YAML.safe_load_file("Procfile")
    rescue Error
      raise
    rescue => e
      raise Error, "Can't read Procfile: #{e.inspect}"
    end

    def parse_formation(formation_string)
      return {} unless formation_string
      formation_string.split(",").map { |f| f.split("=") }.to_h.transform_values(&:to_i)
    end
  end
end
