Feature: Create command
  As a developer
  I want to create systemd services from my Procfile
  So that my application processes run as managed services

  Scenario: Creates services and target from procsd.yml
    Given a procsd.yml with:
      """
      app: myapp
      formation: web=1
      environment:
        PORT: 3000
        RAILS_ENV: production
      processes:
        web:
          ExecStart: /bin/sleep infinity
      """
    When I run "procsd create"
    Then the command should succeed
    And the systemd directory should contain "myapp-web.1.service"
    And the systemd directory should contain "myapp.target"
    And the target "myapp.target" should be enabled
