require 'yaml'
require 'erb'
require_relative 'generator'

module Procsd
  class CLI < Thor
    class ConfigurationError < StandardError; end
    class ArgumentError < StandardError; end

    desc "create", "Create and enable app services"
    option :user, aliases: :u, type: :string, banner: "$USER"
    option :dir,  aliases: :d, type: :string, banner: "$PWD"
    option :path, aliases: :p, type: :string, banner: "$PATH"
    option :'or-restart', type: :boolean, banner: "Create and start app services if not created yet, otherwise restart"
    option :'add-to-sudoers', type: :boolean, banner: "Create sudoers rule at /etc/sudoers.d/app_name to allow manage app target without password prompt"
    def create
      unless system("which", "systemctl", [:out, :err]=>"/dev/null")
        raise ConfigurationError, "Your OS doesn't has systemctl executable available"
      end
      preload!

      if !target_exist?
        opts = {
          user: options["user"] || ENV["USER"],
          dir: options["dir"] || ENV["PWD"],
          path: options["path"] || fetch_path_env
        }

        opts.each do |key, value|
          if value.nil? || value.empty?
            say("Can't fetch value for --#{key}, please provide it as an argument", :red) and return
          else
            say "Value of the --#{key} option: #{value}"
          end
        end

        gen = Generator.new
        gen.export!(services, config: @config, options: options.merge(opts))

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

        sudoers_rule_content = generate_sudoers_rule(opts[:user])
        if options["add-to-sudoers"]
          sudoers_file_temp_path = "/tmp/#{app_name}"
          sudoers_file_dest_path = "#{SUDOERS_DIR}/#{app_name}"
          if Dir.exist?(SUDOERS_DIR)
            File.open(sudoers_file_temp_path, "w") { |f| f.puts sudoers_rule_content }
            execute %W(sudo chown root:root #{sudoers_file_temp_path})
            execute %W(sudo chmod 0440 #{sudoers_file_temp_path})
            if execute %W(sudo mv #{sudoers_file_temp_path} #{sudoers_file_dest_path})
              say("Sudoers file #{sudoers_file_dest_path} was created", :green)
            end
          else
            say "Directory #{SUDOERS_DIR} does not exist, sudoers file wan't created"
          end
        else
          say "Note: add following line to the sudoers file (`$ sudo visudo`) if you don't " \
            "want to type password each time for start/stop/restart commands:"
          puts sudoers_rule_content
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
          execute %W(sudo rm #{path}) and say "Deleted #{path}" if File.exist? path
        end

        if execute %w(sudo systemctl daemon-reload)
          say("Reloaded configuraion (daemon-reload)", :green)
        end
        say("App services were stopped, disabled and removed", :green)

        sudoers_file_path = "#{SUDOERS_DIR}/#{app_name}"
        if File.exist?(sudoers_file_path)
          if yes?("Remove sudoers rule #{sudoers_file_path} ? (yes/no)")
            say("Sudoers file removed", :green) if execute %W(sudo rm #{sudoers_file_path})
          end
        end
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

      command = %w(journalctl --no-pager --no-hostname --all --output short-iso)
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

    desc "config", "Show configuration. Available types: sudoers"
    def config(name)
      preload!

      case name
      when "sudoers"
        say generate_sudoers_rule(ENV["USER"])
      else
        raise ArgumentError, "Wring type of argument: #{name}"
      end
    end

    map exec: :__exec
    desc "exec", "Run app process"
    option :env, type: :boolean, banner: "Require environment defined in procsd.yml"
    def __exec(process_name)
      preload!

      start_cmd = @config[:processes].dig(process_name, "start")
      raise ArgumentError, "Process is not defined: #{process_name}" unless start_cmd

      if options["env"]
        @config[:environment].each { |k, v| @config[:environment][k] = v.to_s }
        exec @config[:environment], start_cmd
      else
        exec start_cmd
      end
    end

    map %w[--version -v] => :__print_version
    desc "--version, -v", "Print the version"
    def __print_version
      puts VERSION
    end

    private

    def generate_sudoers_rule(user)
      commands = []
      systemctl_path = `which systemctl`.strip

      %w(start stop restart).each { |cmd| commands << "#{systemctl_path} #{cmd} #{target_name}" }
      commands << "#{systemctl_path} reload-or-restart #{app_name}-\\* --all" if has_reload?

      "#{user} ALL=NOPASSWD: #{commands.join(', ')}"
    end

    def has_reload?
      services.any? { |_, opts| opts["restart"] }
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
      @config[:systemd_dir]
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
      @config[:app]
    end

    def services
      all = {}
      @config[:processes].each do |process_name, opts|
        opts["count"].times do |i|
          commands = { "start" => opts["start"], "stop" => opts["stop"], "restart" => opts["restart"] }
          all["#{app_name}-#{process_name}.#{i + 1}.service"] = commands
        end
      end

      all
    end

    def preload!
      @config = {}

      raise ConfigurationError, "Config file procsd.yml doesn't exists" unless File.exist? "procsd.yml"
      begin
        procsd = YAML.load(ERB.new(File.read "procsd.yml").result)
      rescue => e
        raise ConfigurationError, "Can't read procsd.yml: #{e.inspect}"
      end

      raise ConfigurationError, "Missing app name in the procsd.yml file" unless procsd["app"]
      @config[:app] = procsd["app"]

      # If procsd.yml doesn't contains processes defined, try to read Procfile
      unless procsd["processes"]
        msg = "Procfile doesn't exists. Define processes in procsd.yml or create Procfile"
        raise ConfigurationError, msg unless File.exist? "Procfile"
        begin
          procfile = YAML.load_file("Procfile")
        rescue => e
          raise ConfigurationError, "Can't read Procfile: #{e.inspect}"
        end
      end

      if procsd["formation"]
        formation = procsd["formation"].split(",").map { |f| f.split("=") }.to_h
        formation.each { |k, v| formation[k] = v.to_i }
      else
        formation = {}
      end

      processes = procsd["processes"] || procfile
      processes.each do |process_name, opts|
        if opts.kind_of?(Hash)
          raise ConfigurationError, "Missing start command for `#{process_name}` process" unless opts["start"]
        else
          processes[process_name] = { "start" => opts }
        end

        unless processes[process_name]["count"]
          processes[process_name]["count"] = formation[process_name] || 1
        end
      end

      @config[:processes] = processes
      @config[:environment] = procsd["environment"] || {}
      @config[:systemd_dir] = procsd["systemd_dir"] || DEFAULT_SYSTEMD_DIR
    end
  end
end
