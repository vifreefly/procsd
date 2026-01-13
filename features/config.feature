Feature: Config command
  As a developer
  I want to preview configuration files
  So that I can see what will be generated before creating services

  Scenario: Shows sudoers content
    Given a procsd.yml with:
      """
      app: myapp
      formation: web=1
      environment:
        PORT: 3000
      processes:
        web:
          ExecStart: /bin/sleep infinity
      """
    When I run "procsd config sudoers"
    Then the command should succeed with:
      """
      testuser ALL=NOPASSWD: /usr/bin/systemctl start myapp.target, /usr/bin/systemctl stop myapp.target, /usr/bin/systemctl restart myapp.target
      """

  Scenario: Shows service content
    Given a procsd.yml with:
      """
      app: myapp
      formation: web=1
      environment:
        PORT: 3000
      processes:
        web:
          ExecStart: /bin/sleep infinity
      """
    When I run "procsd config services"
    Then the command should succeed with:
      """
      Value of the --user option: testuser
      Value of the --dir option: /home/testuser/myapp
      Value of the --path option: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      Service: web (size: 1):
      ---

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

      Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      Environment="PORT=3000"
      ---
      """
