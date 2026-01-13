Feature: Restart command
  As a developer
  I want to restart my application services
  So that my application processes reload with updated code or configuration

  Scenario: Restarts all services
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
    When I run "procsd restart"
    Then the command should succeed with:
      """
      Restarted app services (myapp.target)
      """
    And the target "myapp.target" should be active
    And the service "myapp-web.1.service" should be active

  Scenario: Restarts a specific service
    Given a procsd.yml with:
      """
      app: myapp
      formation: web=1,worker=1
      environment:
        PORT: 3000
      processes:
        web:
          ExecStart: /bin/sleep infinity
        worker:
          ExecStart: /bin/sleep infinity
      """
    When I run "procsd create"
    Then the command should succeed
    When I run "procsd start"
    Then the command should succeed
    When I run "procsd restart web"
    Then the command should succeed with:
      """
      Restarted app service (myapp-web*)
      """
    And the service "myapp-web.1.service" should be active
