require_relative "helper"

class CreateCommandTest < Minitest::Test
  include Helper

  def test_create_command_creates_services_and_target
    create_procsd_yml(<<~YML)
      app: myapp
      formation: web=1
      environment:
        PORT: 3000
        RAILS_ENV: production
      processes:
        web:
          ExecStart: /bin/sleep infinity
    YML

    result = run_procsd("create")
    assert result.success?, "create failed: #{result.output}"

    assert_equal %w[myapp-web.1.service myapp.target],
      container.list_service_files("myapp*").sort

    assert container.service_enabled?("myapp.target"),
      "Target should be enabled"

    assert_equal <<~UNIT, container.read_file("/etc/systemd/system/myapp.target")
      [Unit]
      Wants=myapp-web.1.service

      [Install]
      WantedBy=multi-user.target
    UNIT

    path = container.exec("bash -lc 'echo $PATH'").stdout.strip
    assert_equal <<~UNIT, container.read_file("/etc/systemd/system/myapp-web.1.service")
      [Unit]
      Requires=network.target
      PartOf=myapp.target

      [Service]
      Type=simple
      User=testuser
      WorkingDirectory=/home/testuser/myapp

      ExecStart=/bin/bash -lc '/bin/sleep infinity'


      Restart=always
      RestartSec=1
      TimeoutStopSec=30
      KillMode=mixed
      StandardInput=null
      SyslogIdentifier=%p

      Environment="PATH=#{path}"
      Environment="PORT=3000"
      Environment="RAILS_ENV=production"
    UNIT
  end
end
