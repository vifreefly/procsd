require "test_helper"
require "procsd/generator"

class GeneratorTest < Minitest::Test
  def setup
    @basic_config = {
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

    @basic_options = {
      "user" => "deploy",
      "dir" => "/home/deploy/myapp",
      "path" => "/usr/local/bin:/usr/bin:/bin"
    }
  end

  def test_app_name_and_target_name
    generator = Procsd::Generator.new(@basic_config, @basic_options)

    assert_equal "myapp", generator.app_name
    assert_equal "myapp.target", generator.target_name
  end

  def test_generate_units_basic_service
    generator = Procsd::Generator.new(@basic_config, @basic_options)
    services = generator.generate_units(save: false)

    assert_equal({ "web" => { content: <<~SYSTEMD, size: 1 } }, services)
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
  end

  def test_generate_units_with_all_commands
    config = @basic_config.dup
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

    generator = Procsd::Generator.new(config, @basic_options)
    services = generator.generate_units(save: false)

    assert_equal({ "web" => { content: <<~SYSTEMD, size: 1 } }, services)
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
  end

  def test_generate_units_with_multiple_processes
    config = @basic_config.dup
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

    generator = Procsd::Generator.new(config, @basic_options)
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

    assert_equal({
      "web" => { content: web_content, size: 2 },
      "worker" => { content: worker_content, size: 3 }
    }, services)
  end

  def test_generate_sudoers_without_reload
    generator = Procsd::Generator.new(@basic_config, @basic_options)
    systemctl_path = `which systemctl`.strip

    assert_equal(<<~SUDOERS.chomp, generator.generate_sudoers("deploy", has_reload: false, save: false))
      deploy ALL=NOPASSWD: #{systemctl_path} start myapp.target, #{systemctl_path} stop myapp.target, #{systemctl_path} restart myapp.target
    SUDOERS
  end

  def test_generate_sudoers_with_reload
    generator = Procsd::Generator.new(@basic_config, @basic_options)
    systemctl_path = `which systemctl`.strip

    assert_equal(<<~SUDOERS.chomp, generator.generate_sudoers("deploy", has_reload: true, save: false))
      deploy ALL=NOPASSWD: #{systemctl_path} start myapp.target, #{systemctl_path} stop myapp.target, #{systemctl_path} restart myapp.target, #{systemctl_path} reload-or-restart myapp-\\* --all
    SUDOERS
  end

  def test_generate_nginx_conf
    config = @basic_config.dup
    config[:nginx] = { "server_name" => "example.com" }

    generator = Procsd::Generator.new(config, @basic_options)

    assert_equal(<<~NGINX, generator.generate_nginx_conf(save: false))
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

  def test_generate_nginx_conf_with_custom_public_folder
    config = @basic_config.dup
    config[:nginx] = {
      "server_name" => "example.com",
      "public_folder_path" => "dist"
    }

    generator = Procsd::Generator.new(config, @basic_options)

    assert_equal(<<~NGINX, generator.generate_nginx_conf(save: false))
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

  def test_generate_nginx_conf_with_error_pages
    config = @basic_config.dup
    config[:nginx] = { "server_name" => "example.com" }

    Dir.mktmpdir do |tmpdir|
      options = @basic_options.merge("dir" => tmpdir)
      public_dir = File.join(tmpdir, "public")
      Dir.mkdir(public_dir)
      File.write(File.join(public_dir, "500.html"), "")
      File.write(File.join(public_dir, "404.html"), "")
      File.write(File.join(public_dir, "422.html"), "")

      generator = Procsd::Generator.new(config, options)

      assert_equal(<<~NGINX, generator.generate_nginx_conf(save: false))
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
