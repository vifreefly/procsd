require 'yaml'
require_relative 'generator'

module Procsd
  class CLI < Thor
    class ConfigurationError < StandardError; end
    map %w[--version -v] => :__print_version

    desc "create", "Create and enable app services"
    option :user,  aliases: :u, type: :string, required: true, banner: "$USER"
    option :dir,   aliases: :d, type: :string, required: true, banner: "$PWD"
    option :path,  aliases: :p, type: :string, required: true, banner: "$PATH"
    def create
      preload!

      if !target_exist?
        gen = Generator.new
        gen.export!(services, procsd: @procsd, options: options)

        enable
        if system "sudo", "systemctl", "daemon-reload"
          say("Reloaded configuraion (daemon-reload)", :green)
        end

        say("App services were created and enabled. Run `start` to start them", :green)
      else
        say("App target `#{target_name}` already exists", :red)
      end
    end

    desc "destroy", "Stop, disable and remove app services"
    def destroy
      preload!

      if target_exist?
        stop
        disable

        services.keys.push(target_name).each do |filename|
          path = File.join(systemd_dir, filename)
          if File.exist? path
            system "sudo", "rm", path
            say "Deleted #{path}"
          end
        end

        if system "sudo", "systemctl", "daemon-reload"
          say("Reloaded configuraion (daemon-reload)", :green)
        end

        say("App services were stopped, disabled and removed", :green)
      else
        say_target_not_exists
      end
    end

    desc "enable", "Enable app target"
    def enable
      preload!
      say_target_not_exists and return unless target_exist?

      if target_enabled?
        say "App target #{target_name} already enabled"
      else
        if system "sudo", "systemctl", "enable", target_name
          say("Enabled app target #{target_name}", :green)
        end
      end
    end

    desc "disable", "Disable app target"
    def disable
      preload!
      say_target_not_exists and return unless target_exist?

      if !target_enabled?
        say "App target #{target_name} already disabled"
      else
        if system "sudo", "systemctl", "disable", target_name
          say("Disabled app target #{target_name}", :green)
        end
      end
    end

    desc "start", "Start app services"
    def start
      preload!
      say_target_not_exists and return unless target_exist?

      if target_active?
        say "Already started/active (#{target_name})"
      else
        if system "sudo", "systemctl", "start", target_name
          say("Started app services (#{target_name})", :green)
        end
      end
    end

    desc "stop", "Stop app services"
    def stop
      preload!
      say_target_not_exists and return unless target_exist?

      if !target_active?
        say "Already stopped/inactive (#{target_name})"
      else
        if system "sudo", "systemctl", "stop", target_name
          say("Stopped app services (#{target_name})", :green)
        end
      end
    end

    desc "restart", "Restart app services"
    def restart
      preload!
      say_target_not_exists and return unless target_exist?

      if system "sudo", "systemctl", "restart", target_name
        say("Restarted app services (#{target_name})", :green)
      end
    end

    desc "status", "Show app services status"
    option :target, type: :string, banner: "Show main target status"
    def status(service_name = nil)
      preload!
      say_target_not_exists and return unless target_exist?

      command = %w(systemctl status --no-pager --output short-iso)
      if options["target"]
        command << target_name
      else
        filtered = filter_services(service_name)
        say("Can't find any services matching given name: #{service_name}", :red) and return if filtered.empty?
        command += filtered
      end

      system *command
    end

    desc "logs", "Show app services logs"
    option :num, aliases: :n, type: :string, banner: "How many lines to print"
    option :tail, aliases: [:t, :f], type: :boolean, banner: "Display logs in real-time"
    option :system, type: :boolean, banner: "Show only system messages" # similar to heroku `--source heroku`
    option :priority, aliases: :p, type: :string, banner: "Show messages with a particular log level"
    def logs(service_name = nil)
      preload!

      command = %w(journalctl --no-pager --all --no-hostname --output short-iso)
      command.push("-n", options.fetch("num", "100"))
      command.push("-f") if options["tail"]
      command.push("--system") if options["system"]
      command.push("--priority", options["priority"]) if options["priority"]

      filtered = filter_services(service_name)
      say("Can't find any services matching given name: #{service_name}", :red) and return if filtered.empty?

      filtered.each { |service| command.push("--unit", service) }
      system *command
    end

    desc "--version, -v", "Print the version"
    def __print_version
      puts VERSION
    end

    private

    def say_target_not_exists
      say("App target #{target_name} is not exists", :red)
    end

    def filter_services(service_name)
      if service_name
        services.keys.select { |s| s.include?("#{app_name}-#{service_name}") }
      else
        services.keys
      end
    end

    def target_exist?
      File.exist?(File.join systemd_dir, target_name)
    end

    def systemd_dir
      @procsd["systemd_dir"]
    end

    def target_enabled?
      system "systemctl", "is-enabled", "--quiet", target_name
    end

    def target_active?
      system "systemctl", "is-active", "--quiet", target_name
    end

    def target_name
      "#{app_name}.target"
    end

    def app_name
      @procsd["app"]
    end

    def services
      all = {}
      @procfile.each do |process_name, process_command|
        processes_count = @procsd["formation"][process_name] || 1
        processes_count.times do |i|
          all["#{app_name}-#{process_name}.#{i + 1}.service"] = process_command
        end
      end

      all
    end

    def preload!
      raise ConfigurationError, "Procfile file doesn't exists" unless File.exist? "Procfile"
      raise ConfigurationError, ".procsd.yml config file doesn't exists" unless File.exist? ".procsd.yml"

      @procfile = YAML.load_file("Procfile")
      @procsd = YAML.load_file(".procsd.yml")
      raise ConfigurationError, "Missing app name in the .procsd.yml file" unless @procsd["app"]

      if formation = @procsd["formation"]
        @procsd["formation"] = formation.split(",").map { |f| f.split("=") }.to_h
        @procsd["formation"].each { |k, v| @procsd["formation"][k] = v.to_i }
      else
        @procsd["formation"] = {}
      end

      @procsd["environment"] ||= []
      @procsd["systemd_dir"] ||= DEFAULT_SYSTEMD_DIR
    end
  end
end
