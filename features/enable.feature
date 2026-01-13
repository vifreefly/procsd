Feature: Enable command
  As a developer
  I want to enable my application target
  So that my services start automatically on boot

  Scenario: Enables the app target
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
    When I run "procsd disable"
    Then the command should succeed
    And the target "myapp.target" should not be enabled
    When I run "procsd enable"
    Then the command should succeed with:
      """
      Enabled app target myapp.target
      Created symlink /etc/systemd/system/multi-user.target.wants/myapp.target → /etc/systemd/system/myapp.target.
      """
    And the target "myapp.target" should be enabled
