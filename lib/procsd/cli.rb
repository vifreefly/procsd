require 'yaml'
require 'erb'
require_relative 'generator'

module Procsd
  class CLI < Thor
    class ConfigurationError < StandardError; end
    map %w[--version -v] => :__print_version

    desc "create", "Create and enable app services"
    option :user, aliases: :u, type: :string, required: true, banner: "$USER"
    option :dir,  aliases: :d, type: :string, required: true, banner: "$PWD"
    option :path, aliases: :p, type: :string, banner: "$PATH"
    option :'or-restart', type: :boolean, banner: "Create and start app services if not created yet, otherwise restart"
    def create
      preload!

      if !target_exist?
        opts = options["path"] ? options : options.merge("path" => fetch_path)

        gen = Generator.new
        gen.export!(services, procsd: @procsd, options: opts)

        enable
        if execute %w(sudo systemctl daemon-reload)
          say("Reloaded configuraion (daemon-reload)", :green)
        end

        if options["or-restart"]
          start
          say("App services were created, enabled and started", :green)
        else
          say("App services were created and enabled. Run `start` to start them", :green)
        end
      else
        if options["or-restart"]
          restart
        else
          say("App target `#{target_name}` already exists", :red)
        end
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
            execute %W(sudo rm #{path})
            say "Deleted #{path}"
          end
        end

        if execute %w(sudo systemctl daemon-reload)
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
        if execute %W(sudo systemctl enable #{target_name})
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
        if execute %W(sudo systemctl disable #{target_name})
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
        if execute %W(sudo systemctl start #{target_name})
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
        if execute %W(sudo systemctl stop #{target_name})
          say("Stopped app services (#{target_name})", :green)
        end
      end
    end

    desc "restart", "Restart app services"
    def restart
      preload!
      say_target_not_exists and return unless target_exist?

      # If one of the child services of a target has `ExecReload` and `ReloadPropagatedFrom`
      # options defined, then use `reload-or-restart` to call all services (not the main target)
      # because https://github.com/systemd/systemd/issues/10638
      success =
        if services.any? { |_, command| command["restart"] }
          execute %w(sudo systemctl reload-or-restart) + services.keys
        else
          execute %W(sudo systemctl restart #{target_name})
        end

      if success
        say("Restarted app services (#{target_name})", :green)
      end
    end

    desc "status", "Show app services status"
    option :target, type: :boolean, banner: "Show main target status"
    option :short,  type: :boolean, banner: "Show services three and their status shortly"
    def status(service_name = nil)
      preload!
      say_target_not_exists and return unless target_exist?

      if options["short"]
        command = %w(sudo systemctl list-units --no-pager --no-legend --all)
      else
        command = %w(sudo systemctl status --no-pager --output short-iso)
      end

      if options["target"]
        command << target_name
      else
        filtered = filter_services(service_name)
        say("Can't find any services matching given name: #{service_name}", :red) and return if filtered.empty?
        command += filtered
      end

      execute command
    end

    desc "logs", "Show app services logs"
    option :num, aliases: :n, type: :string, banner: "How many lines to print"
    option :tail, aliases: [:t, :f], type: :boolean, banner: "Display logs in real-time"
    option :system, type: :boolean, banner: "Show only system messages"
    option :priority, aliases: :p, type: :string, banner: "Show messages with a particular log level"
    option :grep, aliases: :g, type: :string, banner: "Filter output to entries where message matches the provided query"
    def logs(service_name = nil)
      preload!

      command = %w(sudo journalctl --no-pager --all --no-hostname --output short-iso)
      command.push("-n", options.fetch("num", "100"))
      command.push("-f") if options["tail"]
      command.push("--system") if options["system"]
      command.push("--priority", options["priority"]) if options["priority"]
      command.push("--grep", "'" + options["grep"] + "'") if options["grep"]

      filtered = filter_services(service_name)
      say("Can't find any services matching given name: #{service_name}", :red) and return if filtered.empty?

      filtered.each { |service| command.push("--unit", service) }
      execute command
    end

    desc "list", "List all app services"
    def list
      preload!
      say_target_not_exists and return unless target_exist?

      execute %W(sudo systemctl list-dependencies #{target_name})
    end

    desc "--version, -v", "Print the version"
    def __print_version
      puts VERSION
    end

    private

    def fetch_path
      # get value of the $PATH env variable including ~/.bashrc as well (-i flag)
      `/bin/bash -ilc 'echo $PATH'`.strip
    end

    def execute(command)
      say("> Executing command: `#{command.join(' ')}`", :yellow) if ENV["VERBOSE"] == "true"
      system *command
    end

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
      @procsd = YAML.load(ERB.new(File.read ".procsd.yml").result)
      raise ConfigurationError, "Missing app name in the .procsd.yml file" unless @procsd["app"]

      @procfile.each do |process_name, process_command|
        if process_command.kind_of?(Hash)
          unless process_command["start"]
            raise ConfigurationError, "Missing start command for #{process_name} process in the Procfile"
          end
        else
          @procfile[process_name] = { "start" => process_command }
        end
      end

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
