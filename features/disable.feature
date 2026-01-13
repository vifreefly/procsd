Feature: Disable command
  As a developer
  I want to disable my application target
  So that my services do not start automatically on boot

  Scenario: Disables the app target
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
    And the target "myapp.target" should be enabled
    When I run "procsd disable"
    Then the command should succeed with:
      """
      Disabled app target myapp.target
      Removed "/etc/systemd/system/multi-user.target.wants/myapp.target".
      """
    And the target "myapp.target" should not be enabled
