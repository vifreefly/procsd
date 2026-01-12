require "procsd/generator"
require "tmpdir"

RSpec.describe Procsd::Generator do
  let(:basic_config) do
    {
      app: "myapp",
      systemd_dir: "/etc/systemd/system",
      environment: {
        "PORT" => "3000",
        "RAILS_ENV" => "production"
      },
      processes: {
        "web" => {
          "commands" => { "ExecStart" => "bundle exec puma -C config/puma.rb" },
          "size" => 1
        }
      }
    }
  end

  let(:basic_options) do
    {
      "user" => "deploy",
      "dir" => "/home/deploy/myapp",
      "path" => "/usr/local/bin:/usr/bin:/bin"
    }
  end

  describe "#app_name and #target_name" do
    it "returns the app name and target name" do
      generator = described_class.new(basic_config, basic_options)

      expect(generator.app_name).to eq("myapp")
      expect(generator.target_name).to eq("myapp.target")
    end
  end

  describe "#generate_units" do
    it "generates a basic service unit" do
      generator = described_class.new(basic_config, basic_options)
      services = generator.generate_units(save: false)

      expect(services).to eq({
        "web" => {
          content: <<~SYSTEMD,
            [Unit]
            Requires=network.target
            PartOf=myapp.target

            [Service]
            Type=simple
            User=deploy
            WorkingDirectory=/home/deploy/myapp

            ExecStart=/bin/bash -lc 'bundle exec puma -C config/puma.rb'


            Restart=always
            RestartSec=1
            TimeoutStopSec=30
            KillMode=mixed
            StandardInput=null
            SyslogIdentifier=%p

            Environment="PATH=/usr/local/bin:/usr/bin:/bin"
            Environment="PORT=3000"
            Environment="RAILS_ENV=production"
          SYSTEMD
          size: 1
        }
      })
    end

    it "generates a service unit with all commands" do
      config = basic_config.dup
      config[:processes] = {
        "web" => {
          "commands" => {
            "ExecStart" => "bundle exec puma",
            "ExecStop" => "bundle exec pumactl stop",
            "ExecReload" => "bundle exec pumactl phased-restart",
            "RuntimeMaxSec" => "86400"
          },
          "size" => 1
        }
      }

      generator = described_class.new(config, basic_options)
      services = generator.generate_units(save: false)

      expect(services).to eq({
        "web" => {
          content: <<~SYSTEMD,
            [Unit]
            Requires=network.target
            PartOf=myapp.target
            ReloadPropagatedFrom=myapp.target

            [Service]
            Type=simple
            User=deploy
            WorkingDirectory=/home/deploy/myapp

            ExecStart=/bin/bash -lc 'bundle exec puma'
            ExecStop=/bin/bash -lc 'bundle exec pumactl stop'
            ExecReload=/bin/bash -lc 'bundle exec pumactl phased-restart'

            RuntimeMaxSec=86400

            Restart=always
            RestartSec=1
            TimeoutStopSec=30
            KillMode=mixed
            StandardInput=null
            SyslogIdentifier=%p

            Environment="PATH=/usr/local/bin:/usr/bin:/bin"
            Environment="PORT=3000"
            Environment="RAILS_ENV=production"
          SYSTEMD
          size: 1
        }
      })
    end

    it "generates units for multiple processes" do
      config = basic_config.dup
      config[:processes] = {
        "web" => {
          "commands" => { "ExecStart" => "bundle exec puma" },
          "size" => 2
        },
        "worker" => {
          "commands" => { "ExecStart" => "bundle exec sidekiq" },
          "size" => 3
        }
      }

      generator = described_class.new(config, basic_options)
      services = generator.generate_units(save: false)

      web_content = <<~SYSTEMD
        [Unit]
        Requires=network.target
        PartOf=myapp.target

        [Service]
        Type=simple
        User=deploy
        WorkingDirectory=/home/deploy/myapp

        ExecStart=/bin/bash -lc 'bundle exec puma'


        Restart=always
        RestartSec=1
        TimeoutStopSec=30
        KillMode=mixed
        StandardInput=null
        SyslogIdentifier=%p

        Environment="PATH=/usr/local/bin:/usr/bin:/bin"
        Environment="PORT=3000"
        Environment="RAILS_ENV=production"
      SYSTEMD

      worker_content = <<~SYSTEMD
        [Unit]
        Requires=network.target
        PartOf=myapp.target

        [Service]
        Type=simple
        User=deploy
        WorkingDirectory=/home/deploy/myapp

        ExecStart=/bin/bash -lc 'bundle exec sidekiq'


        Restart=always
        RestartSec=1
        TimeoutStopSec=30
        KillMode=mixed
        StandardInput=null
        SyslogIdentifier=%p

        Environment="PATH=/usr/local/bin:/usr/bin:/bin"
        Environment="PORT=3000"
        Environment="RAILS_ENV=production"
      SYSTEMD

      expect(services).to eq({
        "web" => { content: web_content, size: 2 },
        "worker" => { content: worker_content, size: 3 }
      })
    end
  end

  describe "#generate_sudoers" do
    let(:systemctl_path) { `which systemctl`.strip }

    it "generates sudoers without reload" do
      generator = described_class.new(basic_config, basic_options)

      expect(generator.generate_sudoers("deploy", has_reload: false, save: false)).to eq(<<~SUDOERS.chomp)
        deploy ALL=NOPASSWD: #{systemctl_path} start myapp.target, #{systemctl_path} stop myapp.target, #{systemctl_path} restart myapp.target
      SUDOERS
    end

    it "generates sudoers with reload" do
      generator = described_class.new(basic_config, basic_options)

      expect(generator.generate_sudoers("deploy", has_reload: true, save: false)).to eq(<<~SUDOERS.chomp)
        deploy ALL=NOPASSWD: #{systemctl_path} start myapp.target, #{systemctl_path} stop myapp.target, #{systemctl_path} restart myapp.target, #{systemctl_path} reload-or-restart myapp-\\* --all
      SUDOERS
    end
  end

  describe "#generate_nginx_conf" do
    it "generates basic nginx config" do
      config = basic_config.dup
      config[:nginx] = { "server_name" => "example.com" }

      generator = described_class.new(config, basic_options)

      expect(generator.generate_nginx_conf(save: false)).to eq(<<~NGINX)
        upstream myapp {
          server 127.0.0.1:3000;
        }

        server {
          listen 80;
          listen [::]:80;

          server_name example.com;
          root /home/deploy/myapp/public;

          location ^~ /assets/ {
            gzip_static on;
            expires max;
            add_header Cache-Control public;
          }

          try_files $uri/index.html $uri @myapp;
          location @myapp {
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $http_host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_redirect off;
            proxy_pass http://myapp;
          }

          client_max_body_size 256M;
          keepalive_timeout 60;
        }
      NGINX
    end

    it "generates nginx config with custom public folder" do
      config = basic_config.dup
      config[:nginx] = {
        "server_name" => "example.com",
        "public_folder_path" => "dist"
      }

      generator = described_class.new(config, basic_options)

      expect(generator.generate_nginx_conf(save: false)).to eq(<<~NGINX)
        upstream myapp {
          server 127.0.0.1:3000;
        }

        server {
          listen 80;
          listen [::]:80;

          server_name example.com;
          root /home/deploy/myapp/dist;

          location ^~ /assets/ {
            gzip_static on;
            expires max;
            add_header Cache-Control public;
          }

          try_files $uri/index.html $uri @myapp;
          location @myapp {
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $http_host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_redirect off;
            proxy_pass http://myapp;
          }

          client_max_body_size 256M;
          keepalive_timeout 60;
        }
      NGINX
    end

    it "generates nginx config with error pages" do
      config = basic_config.dup
      config[:nginx] = { "server_name" => "example.com" }

      Dir.mktmpdir do |tmpdir|
        options = basic_options.merge("dir" => tmpdir)
        public_dir = File.join(tmpdir, "public")
        Dir.mkdir(public_dir)
        File.write(File.join(public_dir, "500.html"), "")
        File.write(File.join(public_dir, "404.html"), "")
        File.write(File.join(public_dir, "422.html"), "")

        generator = described_class.new(config, options)

        expect(generator.generate_nginx_conf(save: false)).to eq(<<~NGINX)
          upstream myapp {
            server 127.0.0.1:3000;
          }

          server {
            listen 80;
            listen [::]:80;

            server_name example.com;
            root #{public_dir};

            location ^~ /assets/ {
              gzip_static on;
              expires max;
              add_header Cache-Control public;
            }

            try_files $uri/index.html $uri @myapp;
            location @myapp {
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header Host $http_host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_redirect off;
              proxy_pass http://myapp;
            }

            client_max_body_size 256M;
            keepalive_timeout 60;
            error_page 500 502 503 504 /500.html;
            error_page 404 /404.html;
            error_page 422 /422.html;
          }
        NGINX
      end
    end
  end
end
