module Procsd
  class Generator
    attr_reader :app_name, :target_name

    def initialize(config = {})
      @config = config
      @app_name = @config[:app]
      @target_name = "#{app_name}.target"
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
