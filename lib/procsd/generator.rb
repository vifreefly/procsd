require 'pathname'

module Procsd
  class Generator < Thor::Group
    include Thor::Actions

    def self.source_root
      File.dirname(__FILE__)
    end

    def export(services, procsd:, options:)
      @procsd = procsd
      set_dest_root

      app_name = @procsd["app"]
      target_name = "#{app_name}.target"

      services.each do |service_name, service_command|
        service_config = options.merge(
          "target_name" => target_name,
          "id" => service_name.sub(".service", ""),
          "command" => service_command,
          "environment" => @procsd["environment"]
        )
        create_service(service_name, service_config)
      end

      target_config = {
        "app" => app_name,
        "services" => services.keys
      }
      create_target(target_name, target_config)
    end

    private

    def create_service(service_name, confing)
      template("templates/service.erb", service_name, confing)
    end

    def create_target(target_name, config)
      template("templates/target.erb", target_name, config)
    end

    def set_dest_root
      self.destination_root = @procsd["systemd_dir"]
      puts "Systemd export directory: #{destination_root}"
    end
  end
end
