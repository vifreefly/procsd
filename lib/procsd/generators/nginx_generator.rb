module Procsd
  class NginxGenerator < Generator
    def generate_nginx!
      nginx_settings = @config[:nginx]

      root_path = File.join(@config[:options]["dir"], "public")
      content = generate_template("nginx", {
        upstream: @config[:app],
        proxy_to: nginx_settings["proxy_to"],
        server_name: nginx_settings["server_name"],
        root: root_path,
        error_500: File.exist?(File.join root_path, "500.html"),
        error_404: File.exist?(File.join root_path, "404.html"),
        error_422: File.exist?(File.join root_path, "422.html")
      })

      puts "Creating Nginx config (#{available_config_path})..."
      write_file!(available_config_path, content)

      puts "Link Nginx config file to the sites-enabled folder..."
      system "sudo", "ln", "-nfs", available_config_path, enabled_config_path

      # Reference: https://certbot.eff.org/docs/using.html#certbot-command-line-options
      # How it works in Caddy https://caddyserver.com/docs/automatic-https
      if nginx_settings["ssl"]
        command = %w(sudo certbot --agree-tos --no-eff-email --redirect --non-interactive --nginx)
        nginx_settings["server_name"].split(" ").map(&:strip).each do |domain|
          command.push("-d", domain)
        end

        if email = ENV["CERTBOT_EMAIL"]
          command.push("--email", email)
        else
          command << "--register-unsafely-without-email"
        end

        puts "Trying to obtain SSL certificate for Nginx config using Certbot..."
        if system *command
          puts "Successfully installed SSL cert using Certbot"
        else
          puts "Failed to install SSL cert using Certbot. Make sure that all provided domains are pointing to this server IP."
        end
      end
    end

    def destroy_nginx!
      [enabled_config_path, available_config_path].each do |path|
        if File.exist?(path)
          system("sudo", "rm", path) and puts "Deleted: #{path}"
        end
      end
    end

    private

    def enabled_config_path
      File.join(NGINX_DIR, "sites-enabled", app_name)
    end

    def available_config_path
      File.join(NGINX_DIR, "sites-available", app_name)
    end
  end
end
