require 'pathname'

module Procsd
  class Generator
    attr_reader :app_name, :target_name

    def initialize(config = {})
      @config = config
      @app_name = @config[:app]
      @target_name = "#{app_name}.target"
    end

    def generate_units(save: false)
      services = {}
      @config[:processes].each do |name, values|
        commands = values["commands"]
        content = generate_template("service", {
          "user" => @config[:options]["user"],
          "dir" => @config[:options]["dir"],
          "path" => @config[:options]["path"],
          "target_name" => target_name,
          "commands" => commands,
          "environment" => @config[:environment]
        })

        services[name] = { content: content, size: values["size"] }
      end

      if save
        puts "Creating app units files in the systemd directory (#{DEFAULT_SYSTEMD_DIR})..."
        wants = []
        services.each do |service_name, values|
          values[:size].times do |i|
            unit_name = "#{app_name}-#{service_name}.#{i + 1}.service"
            wants << unit_name
            write_file!(File.join(@config[:systemd_dir], unit_name), values[:content])
          end
        end

        target_content = generate_template("target", {
          "app" => app_name,
          "wants" => wants.join(" ")
        })
        write_file!(File.join(@config[:systemd_dir], target_name), target_content)
      else
        services
      end
    end

    def generate_sudoers(user, has_reload:, save: false)
      systemctl_path = `which systemctl`.strip
      commands = []
      %w(start stop restart).each { |cmd| commands << "#{systemctl_path} #{cmd} #{target_name}" }
      commands << "#{systemctl_path} reload-or-restart #{app_name}-\\* --all" if has_reload
      content = "#{user} ALL=NOPASSWD: #{commands.join(', ')}"

      if save
        puts "Creating sudoers rule file in the sudoers.d directory (#{SUDOERS_DIR})..."
        temp_path = "/tmp/#{app_name}"
        dest_path = "#{SUDOERS_DIR}/#{app_name}"

        File.open(temp_path, "w") { |f| f.puts content }
        system "sudo", "chown", "root:root", temp_path
        system "sudo", "chmod", "0440", temp_path
        system "sudo", "mv", temp_path, dest_path
      else
        content
      end
    end

    def generate_nginx_conf(save: false)
      root_path = File.join(@config[:options]["dir"], "public")
      content = generate_template("nginx", {
        port: @config[:environment]["PORT"],
        server_name: @config[:nginx]["server_name"],
        root: root_path,
        error_500: File.exist?(File.join root_path, "500.html"),
        error_404: File.exist?(File.join root_path, "404.html"),
        error_422: File.exist?(File.join root_path, "422.html")
      })

      if save
        config_path = File.join(NGINX_DIR, "sites-available", app_name)
        puts "Creating Nginx config (#{config_path})..."
        write_file!(config_path, content)
        puts "Link Nginx config file to the sites-enabled folder..."
        system "sudo", "ln", "-nfs", config_path, File.join(NGINX_DIR, "sites-enabled")
      else
        content
      end
    end

    def generate_template(template_name, conf)
      b = binding
      b.local_variable_set(:config, conf)
      template_path = File.join(File.dirname(__FILE__), "templates/#{template_name}.erb")
      content = File.read(template_path)
      ERB.new(content, nil, "-").result(b)
    end

    def write_file!(dest_path, content)
      temp_path = File.join("/tmp", Pathname.new(dest_path).basename.to_s)
      File.write(temp_path, content)
      if system "sudo", "mv", temp_path, dest_path
        puts "Create: #{dest_path}"
      end
    ensure
      File.delete(temp_path) if File.exist?(temp_path)
    end
  end
end
