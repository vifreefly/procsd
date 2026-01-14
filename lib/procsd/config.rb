require "yaml"
require "erb"

module Procsd
  class Config < Struct.new(:app, :processes, :environment, :dev_environment, :systemd_dir, :nginx)
    class Error < StandardError; end

    def self.load(path = "procsd.yml")
      new(path)
    end

    def initialize(path)
      config_file = read_config_file(path)
      self.app = config_file["app"] || raise(Error, "Missing app name in the procsd.yml file")
      self.processes = load_processes(config_file)
      self.environment = config_file["environment"] || {}
      self.dev_environment = config_file["dev_environment"] || {}
      self.systemd_dir = config_file["systemd_dir"] || Procsd::DEFAULT_SYSTEMD_DIR
      self.nginx = config_file["nginx"]
    end

    private

    def read_config_file path
      raise Error, "Config file #{path} doesn't exist" unless File.exist?(path)
      begin
        config_file = YAML.safe_load(ERB.new(File.read(path)).result)
      rescue => e
        raise Error, "Can't read #{path}: #{e.inspect}"
      end
      config_file
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
