module Procsd
  class Generator
    attr_reader :app_name, :target_name

    def initialize(config, options)
      @config = config
      @options = options
      @app_name = @config[:app]
      @target_name = "#{app_name}.target"
    end

    def generate_export(save: false)
      services = {}
      @config[:processes].each do |name, values|
        commands = values["commands"]
        size = values["size"]
        content = generate_from("service", @options.merge(
          "target_name" => target_name,
          "commands" => commands,
          "environment" => @config[:environment]
        ))

        services[name] = { content: content, size: size }
      end

      if save
        puts "Creating app units files in the systemd directory (#{DEFAULT_SYSTEMD_DIR})..."
        wants = []
        services.each do |service_name, values|
          values[:size].times do |i|
            unit_name = "#{app_name}-#{service_name}.#{i + 1}.service"
            wants << unit_name
            write_unit!(unit_name, values[:content])
          end
        end

        target_content = generate_from("target", {
          "app" => app_name,
          "wants" => wants.join(" ")
        })
        write_unit!(target_name, target_content)
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

    private

    def generate_from(template_name, conf)
      b = binding
      b.local_variable_set(:config, conf)
      template_path = File.join(File.dirname(__FILE__), "templates/#{template_name}.erb")
      content = File.read(template_path)

      ERB.new(content, nil, "-").result(b)
    end

    def write_unit!(filename, content)
      source_path = File.join("/tmp", filename)
      dest_path = File.join(@config[:systemd_dir], filename)

      File.write(source_path, content)
      if system "sudo", "mv", source_path, dest_path
        puts "Create: #{dest_path}"
      end
    ensure
      File.delete(source_path) if File.exist? source_path
    end
  end
end
