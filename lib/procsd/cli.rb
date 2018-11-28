require 'yaml'
require_relative 'generator'

module Procsd
  class CLI < Thor
    class ConfigurationError < StandardError; end
    class ArgumentError < StandardError; end

    desc "create", "Create and enable app services"
    option :user, aliases: :u, type: :string, banner: "$USER", default: ENV["USER"]
    option :group, aliases: :g, type: :string, banner: "$GROUP", default: ""
    option :dir,  aliases: :d, type: :string, banner: "$PWD", default: ENV["PWD"]
    option :path, aliases: :p, type: :string, banner: "$PATH", default: `/bin/bash -ilc 'echo $PATH'`.strip
    option :'or-restart', type: :boolean, banner: "Create and start app services if not created yet, otherwise restart"
    option :'add-to-sudoers', type: :boolean, banner: "Create sudoers rule at /etc/sudoers.d/app_name to allow manage app target without password prompt"
    option :'overwrite', type: :boolean, banner: "Overwrite the service file without warning"
    def create
      raise ConfigurationError, "Can't find systemctl executable available" unless in_path?("systemctl")

      preload!
      if @config[:nginx]
        raise ConfigurationError, "Can't find nginx executable available" unless in_path?("nginx")
        unless Dir.exist?(File.join options["dir"], "public")
          raise ConfigurationError, "Missing 'public' folder to use with Nginx"
        end
        unless @config.dig(:environment, "PORT")
          raise ConfigurationError, "Please provide PORT environment variable in procsd.yml to use with Nginx"
        end
        if @config[:nginx]["ssl"]
          raise ConfigurationError, "Can't find certbot executable available" unless in_path?("certbot")
        end
      end
      
      # Restart the service if the target exists and "--or-restart" flag was passed
      restart if target_exist? and options["or-restart"]
      
      # Create if the target doesn't exist or should be overwritten
      perform_create if !target_exist? or options["overwrite"]
      
      # Warn the user if the target already exists and should not be overwritten
      say("App target `#{target_name}` already exists!", :red) if target_exist? and !options["overwrite"]
    end

    desc "destroy", "Stop, disable and remove app services"
    def destroy
      preload!

      if target_exist?
        stop
        disable

        units.each do |filename|
          path = File.join(systemd_dir, filename)
          execute %W(sudo rm #{path}) and say "Deleted: #{path}" if File.exist?(path)
        end

        if execute %w(sudo systemctl daemon-reload)
          say("Reloaded configuraion (daemon-reload)", :green)
        end
        say("App services were stopped, disabled and removed", :green)

        sudoers_file_path = "#{SUDOERS_DIR}/#{app_name}"
        if system "sudo", "test", "-e", sudoers_file_path
          say("Sudoers file removed", :green) if execute %W(sudo rm #{sudoers_file_path})
        end

        if @config[:nginx]
          enabled_path = File.join(NGINX_DIR, "sites-enabled", app_name)
          available_path = File.join(NGINX_DIR, "sites-available", app_name)
          [enabled_path, available_path].each do |path|
            execute %W(sudo rm #{path}) and say "Deleted: #{path}" if File.exist?(path)
          end

          execute %w(sudo systemctl reload-or-restart nginx)
          say("Nginx config removed and daemon reloaded", :green)
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
    option :short,  type: :boolean, banner: "Show service tree and associated status in abbreviated fashion"
    def status(service_name = nil)
      preload!
      say_target_not_exists and return unless target_exist?

      if options["short"]
        command = %w(systemctl list-units --no-pager --no-legend --all)
      else
        command = %w(systemctl status --no-pager --output short-iso --all)
      end

      command << (options["target"] ? target_name : "#{app_name}-#{service_name}*")
      execute command, type: :exec
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
      execute command, type: :exec
    end

    desc "list", "List all app services"
    def list
      preload!
      say_target_not_exists and return unless target_exist?

      command = %W(systemctl list-dependencies #{target_name})
      execute command, type: :exec
    end

    desc "config", "Print config files based on current settings. Available types: sudoers"
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

      start_cmd = @config[:processes].dig(process_name, "commands", "ExecStart")
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

    def perform_create
      options.each do |key, value|
        next unless %w(user dir path group).include? key
        unless value.nil? || value.empty?
          say("Value of the --#{key} option: #{value}", :yellow)
        end
      end

      generator = Generator.new(@config, options)
      generator.generate_units(save: true)

      if execute %w(sudo systemctl daemon-reload)
        say("Reloaded configuraion (daemon-reload)", :green)
      end

      enable

      if options["or-restart"]
        start
        say("App services were created, enabled and started", :green)
      else
        say("App services were created and enabled. Run `start` to start them", :green)
      end

      if options["add-to-sudoers"]
        if Dir.exist?(SUDOERS_DIR)
          if generator.generate_sudoers(options["user"], has_reload: has_reload?, save: true)
            say("Sudoers file #{SUDOERS_DIR}/#{app_name} was created", :green)
          end
        else
          say("Directory #{SUDOERS_DIR} does not exists, sudoers file wasn't created", :red)
        end
      else if ENV["VERBOSE"] == "true"
        say "Note: add following line to the sudoers file (`$ sudo visudo`) if you don't " \
          "want to type password each time for start/stop/restart commands:"
        say generator.generate_sudoers(options["user"], has_reload: has_reload?)
      end

      if nginx = @config[:nginx]
        generator.generate_nginx_conf(save: true)
        say("Nginx config created", :green)

        # Reference: https://certbot.eff.org/docs/using.html#certbot-command-line-options
        # How it works in Caddy https://caddyserver.com/docs/automatic-https
        if nginx["ssl"]
          command = %w(sudo certbot --agree-tos --no-eff-email --redirect --non-interactive --nginx)
          nginx["server_name"].split(" ").map(&:strip).each do |domain|
            command.push("-d", domain)
          end

          if email = ENV["CERTBOT_EMAIL"]
            command.push("--email", email)
          else
            command << "--register-unsafely-without-email"
          end

          say "Trying to obtain SSL certificate for Nginx config using Certbot..."
          if execute command
            say("Successfully installed SSL cert using Certbot", :green)
          else
            msg = "Failed to install SSL cert using Certbot. Make sure that all provided domains are pointing to this server IP."
            say(msg, :red)
          end
        end

        if execute %w(sudo systemctl reload-or-restart nginx)
          say("Nginx daemon reloaded", :green)
        end
      end
    end

    def in_path?(name)
      system("which", name, [:out, :err] => "/dev/null")
    end

    def has_reload?
      @config[:processes].any? { |name, values| values.dig("commands", "ExecReload") }
    end

    def units
      all = [target_name]
      @config[:processes].each do |name, values|
        values["size"].times { |i| all << "#{app_name}-#{name}.#{i + 1}.service" }
      end

      all
    end

    def execute(command, type: :system)
      say("Execute: #{command.join(" ")}", :yellow) if ENV["VERBOSE"] == "true"
      case type
      when :system
        system *command
      when :exec
        exec *command
      end
    end

    def say_target_not_exists
      say("App target #{target_name} does not exist", :red)
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

    def preload!
      @config = { processes: {}}

      raise ConfigurationError, "Config file procsd.yml doesn't exist!" unless File.exist? "procsd.yml"
      begin
        procsd = YAML.load(ERB.new(File.read "procsd.yml").result)
      rescue => e
        raise ConfigurationError, "Can't read procsd.yml: #{e.inspect}"
      end

      raise ConfigurationError, "Missing app name in procsd.yml file" unless procsd["app"]
      @config[:app] = procsd["app"]

      # If procsd.yml doesn't contains processes defined, try to read Procfile
      unless procsd["processes"]
        msg = "Procfile doesn't exist! Define processes in procsd.yml or create Procfile"
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
          raise ConfigurationError, "Missing ExecStart command for `#{process_name}` process" unless opts["ExecStart"]
          @config[:processes][process_name] = { "commands" => opts }
        else
          @config[:processes][process_name] = { "commands" => { "ExecStart" => opts }}
        end

        @config[:processes][process_name]["size"] = formation[process_name] || 1
      end

      @config[:environment] = procsd["environment"] || {}
      @config[:systemd_dir] = procsd["systemd_dir"] || DEFAULT_SYSTEMD_DIR
      @config[:nginx] = procsd["nginx"]
    end
  end
end
