Feature: Start command
  As a developer
  I want to start my application services
  So that my application processes begin running

  Scenario: Starts all services
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
    Then the command should succeed with:
      """
      Started app services (myapp.target)
      """
    And the target "myapp.target" should be active
    And the service "myapp-web.1.service" should be active

  Scenario: Starts a specific service
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
    When I run "procsd start web"
    Then the command should succeed with:
      """
      Started app service (myapp-web*)
      """
    And the service "myapp-web.1.service" should be active
