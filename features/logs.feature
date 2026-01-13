Feature: Logs command
  As a developer
  I want to view logs from my application services
  So that I can debug and monitor my application

  Scenario: Shows service logs
    Given a procsd.yml with:
      """
      app: myapp
      formation: web=1
      environment:
        PORT: 3000
      processes:
        web:
          ExecStart: ruby -e "STDOUT.sync=true; puts :ServiceStarted; sleep"
      """
    When I run "procsd create"
    Then the command should succeed
    When I run "procsd start"
    Then the command should succeed
    When I wait 2 seconds
    When I run "procsd logs -n 10"
    Then the command should succeed
    And the output should match patterns:
      """
      \d{4}-\d{2}-\d{2}T\S+ myapp-web\.1\[\d+\]: ServiceStarted
      """

  Scenario: Shows logs for a specific service
    Given a procsd.yml with:
      """
      app: myapp
      formation: web=1,worker=1
      environment:
        PORT: 3000
      processes:
        web:
          ExecStart: ruby -e "STDOUT.sync=true; puts :WebStarted; sleep"
        worker:
          ExecStart: ruby -e "STDOUT.sync=true; puts :WorkerStarted; sleep"
      """
    When I run "procsd create"
    Then the command should succeed
    When I run "procsd start"
    Then the command should succeed
    When I wait 2 seconds
    When I run "procsd logs web -n 10"
    Then the command should succeed
    And the output should match patterns:
      """
      \d{4}-\d{2}-\d{2}T\S+ myapp-web\.1\[\d+\]: WebStarted
      """
