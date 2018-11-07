# Procsd

I do like the way how simple is managing of application processes in production on Heroku with [Procfile](https://devcenter.heroku.com/articles/procfile). How easily can be accessed application logs with [heroku logs](https://devcenter.heroku.com/articles/logging) command. Just type `heroku create` and you're good to go.

Can we have something similar on the cheap Ubuntu VPS from DigitalOcean? Yes we can, all we need is a Systemd wrapper which allows to export application processes from Procfile to system services, and control them/check status/access logs using simple commands.

> These days most of Linux distributions (including Ubuntu) has Systemd as a default system processes manager. That's why it is a good idea to use Systemd for managing application processes in production (for simple cases).

## Getting started

> Install `procsd` first: `$ gem install procsd`. Required Ruby version is `>= 2.3.0`.

Let's say you have following application's Procfile:

```yaml
web: bundle exec rails server -p $PORT
worker: bundle exec sidekiq -e $RAILS_ENV
```
and you want to have one instance of web process && two instances of worker process. Create inside application directory `procsd.yml` config file:

```yaml
app: sample_app
formation: web=1,worker=2
environment:
  - PORT=2500
  - RAILS_ENV=production
  - RAILS_LOG_TO_STDOUT=true
```
> The only required option in `procsd.yml` is `app` (application's name). Also you can provide custom Systemd directory path (`systemd_dir` option, default is _/etc/systemd/system_)

Configuration is done.

### Create an application (export to Systemd)
> To disable and remove application from Systemd there is command `$ procsd destroy`.

> Note: `create` command needs to provide a few arguments: _--user_ (name of the current user), _--dir_ (application's working directory) and `--path` (user's $PATH). Usually it's fine to provide them like on example below:

```
deploy@server:~/sample_app$ procsd create -u $USER -d $PWD -p $PATH

Systemd directory: /etc/systemd/system
      create  sample_app-web.1.service
      create  sample_app-worker.1.service
      create  sample_app-worker.2.service
      create  sample_app.target
Created symlink /etc/systemd/system/multi-user.target.wants/sample_app.target → /etc/systemd/system/sample_app.target.
Enabled app target sample_app.target
Reloaded configuraion (daemon-reload)
App services were created and enabled. Run `start` to start them
```

### Start application
> Other control commands: `stop` and `restart`

```
deploy@server:~/sample_app$ procsd start

Started app services (sample_app.target)
```


### Check the status
> You can filter processes, like `$ procsd status worker` (show status only for worker processes) or `$ procsd status worker.2` (show status only for worker.2 process)

> To show status of the main application target: `$ procsd status --target`

```
deploy@server:~/sample_app$ procsd status

● sample_app-web.1.service
   Loaded: loaded (/etc/systemd/system/sample_app-web.1.service; static; vendor preset: enabled)
   Active: active (running) since Sun 2018-11-04 01:54:15 +04; 1min 51s ago
 Main PID: 8828 (ruby)
    Tasks: 13 (limit: 4915)
   Memory: 83.6M
   CGroup: /system.slice/sample_app-web.1.service
           └─8828 puma 3.12.0 (tcp://0.0.0.0:2500) [sample_app]

2018-11-04T01:54:15+0400 systemd[1]: Started sample_app-web.1.service.
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: => Booting Puma
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: => Rails 5.2.1 application starting in production
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: => Run `rails server -h` for more startup options
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: Puma starting in single mode...
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: * Version 3.12.0 (ruby 2.3.0-p0), codename: Llamas in Pajamas
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: * Min threads: 5, max threads: 5
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: * Environment: production
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: * Listening on tcp://0.0.0.0:2500
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: Use Ctrl-C to stop

● sample_app-worker.1.service
   Loaded: loaded (/etc/systemd/system/sample_app-worker.1.service; static; vendor preset: enabled)
   Active: active (running) since Sun 2018-11-04 01:54:15 +04; 1min 51s ago
 Main PID: 8826 (bundle)
    Tasks: 15 (limit: 4915)
   Memory: 87.8M
   CGroup: /system.slice/sample_app-worker.1.service
           └─8826 sidekiq 5.2.2 sample_app [0 of 10 busy]

2018-11-04T01:54:15+0400 systemd[1]: Started sample_app-worker.1.service.
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.655Z 8826 TID-grcvqfyom INFO: Running in ruby 2.3.0p0 (2015-12-25 revision 53290) [x86_64-linux]
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.655Z 8826 TID-grcvqfyom INFO: See LICENSE and the LGPL-3.0 for licensing details.
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.655Z 8826 TID-grcvqfyom INFO: Upgrade to Sidekiq Pro for more features and support: http://sidekiq.org
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.655Z 8826 TID-grcvqfyom INFO: Booting Sidekiq 5.2.2 with redis options {:id=>"Sidekiq-serv…, :url=>nil}
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.658Z 8826 TID-grcvqfyom INFO: Starting processing, hit Ctrl-C to stop

● sample_app-worker.2.service
   Loaded: loaded (/etc/systemd/system/sample_app-worker.2.service; static; vendor preset: enabled)
   Active: active (running) since Sun 2018-11-04 01:54:15 +04; 1min 51s ago
 Main PID: 8827 (bundle)
    Tasks: 15 (limit: 4915)
   Memory: 87.8M
   CGroup: /system.slice/sample_app-worker.2.service
           └─8827 sidekiq 5.2.2 sample_app [0 of 10 busy]

2018-11-04T01:54:15+0400 systemd[1]: Started sample_app-worker.2.service.
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.713Z 8827 TID-gniahzm1r INFO: Running in ruby 2.3.0p0 (2015-12-25 revision 53290) [x86_64-linux]
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.713Z 8827 TID-gniahzm1r INFO: See LICENSE and the LGPL-3.0 for licensing details.
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.714Z 8827 TID-gniahzm1r INFO: Upgrade to Sidekiq Pro for more features and support: http://sidekiq.org
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.714Z 8827 TID-gniahzm1r INFO: Booting Sidekiq 5.2.2 with redis options {:id=>"Sidekiq-serv…, :url=>nil}
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.716Z 8827 TID-gniahzm1r INFO: Starting processing, hit Ctrl-C to stop
```

Also you can see status in a short format:

```
deploy@server:~/sample_app$ procsd status --short

sample_app-web.1.service    loaded active running sample_app-web.1.service
sample_app-worker.1.service loaded active running sample_app-worker.1.service
sample_app-worker.2.service loaded active running sample_app-worker.2.service
```


### Check the logs
> Like with command `status`, you can filter logs by passing the name of process as an argument: `$ procsd logs web` (show logs only for web processes, if any)

```
deploy@server:~/sample_app$ procsd logs

-- Logs begin at Sun 2018-10-21 00:38:42 +04, end at Sun 2018-11-04 01:54:17 +04. --
2018-11-04T01:54:15+0400 systemd[1]: Started sample_app-worker.1.service.
2018-11-04T01:54:15+0400 systemd[1]: Started sample_app-worker.2.service.
2018-11-04T01:54:15+0400 systemd[1]: Started sample_app-web.1.service.
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.655Z 8826 TID-grcvqfyom INFO: Running in ruby 2.3.0p0 (2015-12-25 revision 53290) [x86_64-linux]
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.655Z 8826 TID-grcvqfyom INFO: See LICENSE and the LGPL-3.0 for licensing details.
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.655Z 8826 TID-grcvqfyom INFO: Upgrade to Sidekiq Pro for more features and support: http://sidekiq.org
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.655Z 8826 TID-grcvqfyom INFO: Booting Sidekiq 5.2.2 with redis options {:id=>"Sidekiq-server-PID-8826", :url=>nil}
2018-11-04T01:54:17+0400 sample_app-worker.1[8826]: 2018-11-03T21:54:17.658Z 8826 TID-grcvqfyom INFO: Starting processing, hit Ctrl-C to stop
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.713Z 8827 TID-gniahzm1r INFO: Running in ruby 2.3.0p0 (2015-12-25 revision 53290) [x86_64-linux]
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.713Z 8827 TID-gniahzm1r INFO: See LICENSE and the LGPL-3.0 for licensing details.
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.714Z 8827 TID-gniahzm1r INFO: Upgrade to Sidekiq Pro for more features and support: http://sidekiq.org
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.714Z 8827 TID-gniahzm1r INFO: Booting Sidekiq 5.2.2 with redis options {:id=>"Sidekiq-server-PID-8827", :url=>nil}
2018-11-04T01:54:17+0400 sample_app-worker.2[8827]: 2018-11-03T21:54:17.716Z 8827 TID-gniahzm1r INFO: Starting processing, hit Ctrl-C to stop
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: => Booting Puma
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: => Rails 5.2.1 application starting in production
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: => Run `rails server -h` for more startup options
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: Puma starting in single mode...
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: * Version 3.12.0 (ruby 2.3.0-p0), codename: Llamas in Pajamas
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: * Min threads: 5, max threads: 5
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: * Environment: production
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: * Listening on tcp://0.0.0.0:2500
2018-11-04T01:54:17+0400 sample_app-web.1[8828]: Use Ctrl-C to stop
```

Systemd provides [a lot of possibilities](https://www.digitalocean.com/community/tutorials/how-to-use-journalctl-to-view-and-manipulate-systemd-logs) to display and manage application logs (`journalctl` command). Procsd supports following options:
* `-n` - Specify how many last lines to print. Default is 100
* `-t` - Tail, display recent logs and leave the session open for real-time logs to stream in
* `--system` - Show only systemd messages about services (start/stop/restart/fail etc.)
* `--priority` - Filter messages by a [particular log level.](https://www.digitalocean.com/community/tutorials/how-to-use-journalctl-to-view-and-manipulate-systemd-logs#by-priority) For example show only error messages: `procsd logs --priority err`
* `--grep` - [Filter output](https://www.freedesktop.org/software/systemd/man/journalctl.html#-g) to messages where message matches the provided query (may not work for [some](https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1751006) Linux distributions)

## All available commands

```
$ procsd --help

Commands:
  procsd --version, -v                                         # Print the version
  procsd create d, --dir=$PWD p, --path=$PATH u, --user=$USER  # Create and enable app services
  procsd destroy                                               # Stop, disable and remove app services
  procsd disable                                               # Disable app target
  procsd enable                                                # Enable app target
  procsd help [COMMAND]                                        # Describe available commands or one specific command
  procsd list                                                  # List all app services
  procsd logs                                                  # Show app services logs
  procsd restart                                               # Restart app services
  procsd start                                                 # Start app services
  procsd status                                                # Show app services status
  procsd stop                                                  # Stop app services
```


## Difference with Foreman

[Foreman](http://ddollar.github.io/foreman/) itself designed for _development_ (not production) usage only and doing it great. Yes, Foreman allows to [export](http://ddollar.github.io/foreman/#EXPORTING) Procfile to the Systemd, but that's all. After export you have to manually use `systemctl` and `journalctl` to manage/check exported services. Procsd not only exports application, but provides [simple commands](#all-available-commands) to manage exported target.

There is another difference in the export logic. Foreman systemd export uses [dymamic](https://fedoramagazine.org/systemd-template-unit-files/) services templates and as a result generates a lot of files/folders in the systemd directory even for a simple application.

Services names contains [$PORT variable](http://ddollar.github.io/foreman/#PROCFILE) at the end. If Procfile has multiple processes, each exported service will have following naming format: `<app_name>-<process_name>@<port_varible_number += 100>.service` (and it's [undocumented](http://ddollar.github.io/foreman/#SYSTEMD-EXPORT) logic). For example for Procfile and formation (_web=1, worker=2_) above, exported services with Foreman will be: `sample_app-web@2500.service`, `sample_app-worker@2600.service` and `sample_app-worker@2601.service`. My opinion about this approach: it's complicated. Why is there PORT variable, which is also incremented for each service? How I'm supposed to remember all these services names to manage or check services status/logs (it's required to provide full names of services for systemctl/journalctl)?

Procsd following one rule: simplicity. For export it uses static service files (that means for each process will be generated it's own service file) and services names have predictable, Heroku-like names.


## Notes

* If you want to set environment variables per process, [use format](https://github.com/ddollar/foreman/wiki/Per-Process-Environment-Variables) like Foreman recommends.
* To print commands before execution, provide env variable `VERBOSE=true` before procsd command. Example:

```
deploy@server:~/sample_app$ VERBOSE=true procsd logs -n 3

> Executing command: journalctl --no-pager --all --no-hostname --output short-iso -n 3 --unit sample_app-web.1.service --unit sample_app-worker.1.service --unit sample_app-worker.2.service

-- Logs begin at Sun 2018-10-21 00:38:42 +04, end at Sun 2018-11-04 19:17:01 +04. --
2018-11-04T19:11:59+0400 sample_app-worker.2[29907]: 2018-11-04T15:11:59.597Z 29907 TID-gne5aeyuz INFO: Upgrade to Sidekiq Pro for more features and support: http://sidekiq.org
2018-11-04T19:11:59+0400 sample_app-worker.2[29907]: 2018-11-04T15:11:59.597Z 29907 TID-gne5aeyuz INFO: Booting Sidekiq 5.2.2 with redis options {:id=>"Sidekiq-server-PID-29907", :url=>nil}
2018-11-04T19:11:59+0400 sample_app-worker.2[29907]: 2018-11-04T15:11:59.601Z 29907 TID-gne5aeyuz INFO: Starting processing, hit Ctrl-C to stop
```
* You can use extended format of a Procfile to provide additional restart/stop commands for a process:
> Keep in mind that syntax below is not supported by Foreman or Heroku

> All possible options: `start`, `restart` and `stop`

```yml
web:
  start: bundle exec rails server -p $PORT
  restart: bundle exec pumactl phased-restart
worker: bundle exec sidekiq -e production
```

Why? For example default Ruby on Rails application server [Puma](http://puma.io/) supports [Phased or Rolling restart](https://github.com/puma/puma/blob/master/docs/restart.md#normal-vs-hot-vs-phased-restart) feature. If you provide separate `restart`command for a process, then this command will be called (`$ procsd restart`) by Systemd instead of just killing and starting process again.


## ToDo
* Add Capistrano integration examples
* Optional possibility to generate Ngnix config (with out-of-box SSL using [Certbot](https://certbot.eff.org/lets-encrypt/ubuntubionic-nginx)) for an application to use Ngnix as a proxy and serve static files
* Add integration with [Inspeqtor](https://github.com/mperham/inspeqtor) to monitor application services and get alert notifications if something happened


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
