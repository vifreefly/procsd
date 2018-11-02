module Procsd
  class Generator < Thor::Group
    include Thor::Actions

    def self.source_root
      File.dirname(__FILE__)
    end

    def export!(services, procsd:, options:)
      self.destination_root = "/tmp"
      @procsd = procsd
      say "Systemd directory: #{@procsd["systemd_dir"]}"

      app_name = @procsd["app"]
      target_name = "#{app_name}.target"

      services.each do |service_name, service_command|
        service_config = options.merge(
          "target_name" => target_name,
          "id" => service_name.sub(".service", ""),
          "command" => service_command,
          "environment" => @procsd["environment"]
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

    def generate(filename, confing, type:)
      template("templates/#{type}.erb", filename, confing)

      source_path = File.join(destination_root, filename)
      dest_path = File.join(@procsd["systemd_dir"], filename)
      system "sudo", "mv", source_path, dest_path
    end
  end
end
