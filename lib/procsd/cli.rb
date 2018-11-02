require 'yaml'
require_relative 'generator'

module Procsd
  class CLI < Thor
    map %w[--version -v] => :__print_version

    desc "create", "Export to systemd, enable and start all services"
    option :path,  aliases: :p, type: :string, required: true, banner: "$PATH"
    option :home,  aliases: :h, type: :string, required: true, banner: "$HOME"
    option :shell, aliases: :s, type: :string, required: true, banner: "$SHELL"
    option :user,  aliases: :u, type: :string, required: true, banner: "$USER"
    option :dir,   aliases: :d, type: :string, required: true, banner: "$PWD"
    def create
      set_environment

      unless target_exist?
        gen = Generator.new
        gen.export(services, procsd: @procsd, options: options)

        enable
        if system "sudo", "systemctl", "daemon-reload"
          say("Reloaded configuraion (daemon-reload)", :green)
        end

        say("App services exported to systemd and main target enabled. Run `start` to start all services", :green)
      else
        say("Target `#{target_name}` already exist", :red)
      end
    end

    desc "destroy", "Stop, disable and remove systemd services"
    def destroy
      set_environment

      if target_exist?
        stop
        disable

        services.keys.push(target_name).each do |filename|
          path = File.join(systemd_dir, filename)
          if File.exist? path
            system "sudo", "rm", path
            say "Deleted file #{path}"
          end
        end

        if system "sudo", "systemctl", "daemon-reload"
          say("Reloaded configuraion (daemon-reload)", :green)
        end

        say("Services were stopped, disabled and removed", :green)
      else
        say("No such target to destroy: `#{target_name}`", :red)
      end
    end

    desc "enable", "Enable target"
    def enable
      set_environment
      say("Target #{target_name} not exist", :red) and return unless target_exist?

      if target_enabled?
        say "Already enabled (#{target_name})"
      else
        if system "sudo", "systemctl", "enable", target_name
          say("Target enabled (#{target_name})", :green)
        end
      end
    end

    desc "disable", "Disable target"
    def disable
      set_environment
      say("Target #{target_name} not exist", :red) and return unless target_exist?

      unless target_enabled?
        say "Already disabled (#{target_name})"
      else
        if system "sudo", "systemctl", "disable", target_name
          say("Target disabled (#{target_name})", :green)
        end
      end
    end

    desc "start", "Start services"
    def start
      set_environment
      say("Target #{target_name} not exist", :red) and return unless target_exist?

      if target_active?
        say "Already started/active (#{target_name})"
      else
        if system "sudo", "systemctl", "start", target_name
          say("Services started (#{target_name})", :green)
        end
      end
    end

    desc "stop", "Stop services"
    def stop
      set_environment
      say("Target #{target_name} not exist", :red) and return unless target_exist?

      unless target_active?
        say "Already stopped/inactive (#{target_name})"
      else
        if system "sudo", "systemctl", "stop", target_name
          say("Services stopped (#{target_name})", :green)
        end
      end
    end

    desc "restart", "Restart services"
    def restart
      set_environment
      say("Target #{target_name} not exist", :red) and return unless target_exist?

      if system "sudo", "systemctl", "restart", target_name
        say("Services restarted (#{target_name})", :green)
      end
    end

    desc "status", "Show services status"
    option :target, type: :string, banner: "Show main target status"
    def status(service_name = nil)
      set_environment
      say("Target #{target_name} not exist", :red) and return unless target_exist?

      command = ["systemctl", "status", "--no-pager", "--output", "short-iso"]
      if options["target"]
        command << target_name
      else
        filtered = filter_services(service_name)
        say("There are no services which included `#{service_name}`", :red) and return if filtered.empty?
        command += filtered
      end

      system *command
    end

    desc "logs", "Show services logs"
    option :num, aliases: :n, type: :string, banner: "How many lines to print"
    option :tail, aliases: [:t, :f], type: :boolean, banner: "Display logs in real-time"
    option :system, type: :boolean, banner: "Show only system messages" # similar to heroku `--source heroku`
    option :priority, aliases: :p, type: :string, banner: "Show messages with a particular log level"
    def logs(service_name = nil)
      set_environment

      command = ["journalctl", "--no-pager", "--all", "--no-hostname", "--output", "short-iso"]
      command.push("-n", options.fetch("num", "100"))
      command.push("-f") if options["tail"]
      command.push("--system") if options["system"]
      command.push("--priority", options["priority"]) if options["priority"]

      filtered = filter_services(service_name)
      say("There are no services which included `#{service_name}`", :red) and return if filtered.empty?

      filtered.each { |service| command.push("--unit", service) }
      system *command
    end

    desc "--version, -v", "Print the version"
    def __print_version
      puts VERSION
    end

    private

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

    def set_environment
      raise "`Procfile` file does not exists" unless File.exist? "Procfile"
      raise "`.procsd.yml` config file does not exists" unless File.exist? ".procsd.yml"

      @procfile = YAML.load_file("Procfile")
      @procsd = YAML.load_file(".procsd.yml")
      raise "Missing app name in the `.procsd.yml` file" unless @procsd["app"]

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
