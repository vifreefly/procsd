module Procsd
  class Generator < Thor::Group
    include Thor::Actions

    def self.source_root
      File.dirname(__FILE__)
    end

    def export!(services, config:, options:)
      self.destination_root = "/tmp"
      @config = config
      say "Systemd directory: #{@config[:systemd_dir]}"

      app_name = @config[:app]
      target_name = "#{app_name}.target"

      services.each do |service_name, service_command|
        service_config = options.merge(
          "target_name" => target_name,
          "id" => service_name.sub(".service", ""),
          "command" => service_command,
          "environment" => @config[:environment]
        )

        generate(service_name, service_config, type: :service)
      end

      target_config = {
        "app" => app_name,
        "services" => services.keys
      }
      generate(target_name, target_config, type: :target)
    end

    private

    def generate(filename, conf, type:)
      template("templates/#{type}.erb", filename, conf)

      source_path = File.join(destination_root, filename)
      dest_path = File.join(@config[:systemd_dir], filename)
      system "sudo", "mv", source_path, dest_path
    ensure
      File.delete(source_path) if File.exist? source_path
    end
  end
end
