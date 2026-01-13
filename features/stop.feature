Feature: Stop command
  As a developer
  I want to stop my application services
  So that my application processes stop running

  Scenario: Stops all services
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
    And the target "myapp.target" should be active
    When I run "procsd stop"
    Then the command should succeed with:
      """
      Stopped app services (myapp.target)
      """
    And the target "myapp.target" should not be active
    And the service "myapp-web.1.service" should not be active

  Scenario: Stops a specific service
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
    When I run "procsd stop web"
    Then the command should succeed with:
      """
      Stopped app service (myapp-web*)
      """
    And the service "myapp-web.1.service" should not be active
