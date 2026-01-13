Feature: List command
  As a developer
  I want to list all my application services
  So that I can see what services are configured

  Scenario: Shows all services
    Given a procsd.yml with:
      """
      app: myapp
      formation: web=1,worker=2
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
    When I run "procsd list"
    Then the command should succeed with:
      """
      myapp.target
      ○ ├─myapp-web.1.service
      ○ ├─myapp-worker.1.service
      ○ └─myapp-worker.2.service
      """
