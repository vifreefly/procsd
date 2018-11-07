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
        opts = options["path"] ? options : options.merge("path" => fetch_path_env)

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

        say "Note: add following line to the sudoers file (`$ sudo visudo`) if you don't " \
          "want to type password each time for start/stop/restart commands:"
        say generate_sudoers_rule(options["user"])
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

      say "Note: app target #{target_name} already enabled" if target_enabled?
      if execute %W(sudo systemctl enable #{target_name})
        say("Enabled app target #{target_name}", :green)
      end
    end

    desc "disable", "Disable app target"
    def disable
      preload!
      say_target_not_exists and return unless target_exist?

      say "Note: app target #{target_name} already disabled" if !target_enabled?
      if execute %W(sudo systemctl disable #{target_name})
        say("Disabled app target #{target_name}", :green)
      end
    end

    desc "start", "Start app services"
    def start
      preload!
      say_target_not_exists and return unless target_exist?


      say "Note: app target #{target_name} already started/active" if target_active?
      if execute %W(sudo systemctl start #{target_name})
        say("Started app services (#{target_name})", :green)
      end
    end

    desc "stop", "Stop app services"
    def stop
      preload!
      say_target_not_exists and return unless target_exist?

      say "Note: app target #{target_name} already stopped/inactive" if !target_active?
      if execute %W(sudo systemctl stop #{target_name})
        say("Stopped app services (#{target_name})", :green)
      end
    end

    desc "restart", "Restart app services"
    def restart
      preload!
      say_target_not_exists and return unless target_exist?

      # If one of the child services of a target has `ExecReload` and `ReloadPropagatedFrom`
      # options defined, then use `reload-or-restart` to call all services (not the main target)
      # because of systemd bug https://github.com/systemd/systemd/issues/10638
      success =
        if has_reload?
          execute %W(sudo systemctl reload-or-restart #{app_name}-* --all)
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
        command = %w(systemctl list-units --no-pager --no-legend --all)
      else
        command = %w(systemctl status --no-pager --output short-iso --all)
      end

      command << (options["target"] ? target_name : "#{app_name}-#{service_name}*")
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

      command = %w(journalctl --no-pager --no-hostname --output short-iso)
      command.push("-n", options.fetch("num", "100"))
      command.push("-f") if options["tail"]
      command.push("--system") if options["system"]
      command.push("--priority", options["priority"]) if options["priority"]
      command.push("--grep", "'" + options["grep"] + "'") if options["grep"]

      command.push("--unit", "#{app_name}-#{service_name}*")
      execute command
    end

    desc "list", "List all app services"
    def list
      preload!
      say_target_not_exists and return unless target_exist?

      execute %W(systemctl list-dependencies #{target_name})
    end

    desc "--version, -v", "Print the version"
    def __print_version
      puts VERSION
    end

    private

    def generate_sudoers_rule(user)
      commands = []
      systemctl_path = `which systemctl`.strip

      %w(start stop restart).each do |cmd|
        commands << "#{systemctl_path} #{cmd} #{target_name}"
      end
      commands << "#{systemctl_path} reload-or-restart #{app_name}-\\* --all" if has_reload?

      "#{user} ALL=NOPASSWD: #{commands.join(', ')}"
    end

    def has_reload?
      services.any? { |_, command| command["restart"] }
    end

    def fetch_path_env
      # get value of the $PATH env variable including ~/.bashrc as well (-i flag)
      `/bin/bash -ilc 'echo $PATH'`.strip
    end

    def execute(command)
      trap("INT") { puts "\nInterrupted" ; exit 130 }

      say("> Executing command: `#{command.join(' ')}`", :yellow) if ENV["VERBOSE"] == "true"
      system *command
    end

    def say_target_not_exists
      say("App target #{target_name} is not exists", :red)
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
      raise ConfigurationError, "File Procfile doesn't exists" unless File.exist? "Procfile"
      raise ConfigurationError, "File procsd.yml doesn't exists" unless File.exist? "procsd.yml"

      @procfile = YAML.load_file("Procfile")
      @procsd = YAML.load(ERB.new(File.read "procsd.yml").result)
      raise ConfigurationError, "Missing app name in the procsd.yml file" unless @procsd["app"]

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
