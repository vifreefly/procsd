Feature: Destroy command
  As a developer
  I want to destroy my application services
  So that all systemd units are removed from the system

  Scenario: Removes services and target
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
    When I run "procsd create"
    Then the command should succeed
    When I run "procsd start"
    Then the command should succeed
    And the systemd directory should contain "myapp-web.1.service"
    And the systemd directory should contain "myapp.target"
    When I run "procsd destroy"
    Then the command should succeed with:
      """
      Stopped app services (myapp.target)
      Disabled app target myapp.target
      Deleted: /etc/systemd/system/myapp.target
      Deleted: /etc/systemd/system/myapp-web.1.service
      Reloaded configuration (daemon-reload)
      App services were stopped, disabled and removed
      Removed "/etc/systemd/system/multi-user.target.wants/myapp.target".
      """
    And the systemd directory should not contain "myapp-web.1.service"
    And the systemd directory should not contain "myapp.target"
    And the target "myapp.target" should not be active
    And the target "myapp.target" should not be enabled
