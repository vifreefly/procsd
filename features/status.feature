Feature: Status command
  As a developer
  I want to check the status of my application services
  So that I can see if they are running correctly

  Scenario: Shows service status
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
    When I run "procsd status --short"
    Then the command should succeed with:
      """
      myapp-web.1.service loaded active running myapp-web.1.service
      """

  Scenario: Shows target status with --target option
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
    When I run "procsd status --target --short"
    Then the command should succeed with:
      """
      myapp.target loaded active active myapp.target
      """
