module Procsd
  class UnitsGenerator < Generator
    def generate_units!
      services = {}
      @config[:processes].each do |name, values|
        commands = values["commands"]
        content = generate_service_content(commands)
        services[name] = { content: content, size: values["size"] }
      end

      puts "Creating services units files in the systemd directory (#{DEFAULT_SYSTEMD_DIR})..."
      wants = []
      services.each do |service_name, values|
        values[:size].times do |i|
          unit_name = "#{app_name}-#{service_name}.#{i + 1}.service"
          wants << unit_name
          write_file!(File.join(@config[:systemd_dir], unit_name), values[:content])
        end
      end

      puts "Creating main target unit file in the systemd directory (#{DEFAULT_SYSTEMD_DIR})..."
      target_content = generate_target_content(wants)
      write_file!(File.join(@config[:systemd_dir], target_name), target_content)
    end

    private

    def generate_target_content(wants)
      generate_template("target", {
        "app" => app_name,
        "wants" => wants.join(" ")
      })
    end

    def generate_service_content(commands)
      generate_template("service", {
        "user" => @config[:options]["user"],
        "dir" => @config[:options]["dir"],
        "path" => @config[:options]["path"],
        "group" => @config[:options]["group"],
        "target_name" => target_name,
        "commands" => commands,
        "environment" => @config[:environment]
      })
    end
  end
end
