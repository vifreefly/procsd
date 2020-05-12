# Procsd

I do like the way how simple is managing of application processes in production on Heroku with [Procfile](https://devcenter.heroku.com/articles/procfile). How easily can be accessed application logs with [heroku logs](https://devcenter.heroku.com/articles/logging) command. Just type `heroku create` and you're good to go.

Can we have something similar on the cheap Ubuntu VPS from DigitalOcean? Yes we can, all we need is a **systemd wrapper** which allows to export application processes from Procfile to system services, and control them/check status/access logs using simple commands.

> These days most of Linux distributions (including Ubuntu) has systemd as a default system processes manager. That's why it is a good idea to use systemd for managing application processes in production (for simple cases).

## Getting started

> **Note:** latest version of Procsd is `0.5.3`. Since version `0.4.0` there are some breaking changes. Check the [CHANGELOG.md](CHANGELOG.md). To update to the latest version, run `$ gem update procsd` or `$ bundle update procsd` (if you have already installed procsd).

> **Note:** Procsd works best with Capistrano integration: [vifreefly/capistrano-procsd](https://github.com/vifreefly/capistrano-procsd)

Install `procsd` first: `$ gem install procsd`. Required Ruby version is `>= 2.3.0`.

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
  PORT: 2501
  RAILS_ENV: production
  RAILS_LOG_TO_STDOUT: true
```

> The only required option in `procsd.yml` is `app` (application name). Also you can provide custom Systemd directory path (`systemd_dir` option, default is _/etc/systemd/system_)

Configuration is done.

### Create an application (export to Systemd)
> To disable and remove application from Systemd there is command `$ procsd destroy`.

```
deploy@server:~/sample_app$ procsd create

Value of the --user option: deploy
Value of the --dir option: /home/deploy/sample_app
Value of the --path option: /home/deploy/.rbenv/shims:/home/deploy/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin

Creating app units files in the systemd directory (/etc/systemd/system)...
Create: /etc/systemd/system/sample_app-web.1.service
Create: /etc/systemd/system/sample_app-worker.1.service
Create: /etc/systemd/system/sample_app-worker.2.service
Create: /etc/systemd/system/sample_app.target
Reloaded configuraion (daemon-reload)
Created symlink /etc/systemd/system/multi-user.target.wants/sample_app.target → /etc/systemd/system/sample_app.target.
Enabled app target sample_app.target
App services were created and enabled. Run `start` to start them

Note: add following line to the sudoers file (`$ sudo visudo`) if you don't want to type password each time for start/stop/restart commands:
deploy ALL=NOPASSWD: /bin/systemctl start sample_app.target, /bin/systemctl stop sample_app.target, /bin/systemctl restart sample_app.target
```

You can provide additional options for `create` command:
* `--user` - name of the user, default is current _$USER_ env variable
* `--dir` - application's working directory, default is current _$PWD_ env variable
* `--path` - $PATH to include to the each service. Default is current _$PATH_ env variable
* `--add-to-sudoers` - if option present, procsd will create sudoers rule file `/etc/sudoers.d/app_name` which allow to start/stop/restart app services without a password prompt (passwordless sudo).
* `--or-restart` - if option provided and services already created, procsd will skip creation and call instead `restart` command. Otherwise (if services are not present), they will be created and (in additional) started. It's useful option for deployment tools like Capistrano, Mina, etc.


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

Also you can see status in short format:

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

### Execute processes defined in Procfile

Currently, procsd can not run all processes in development like `foreman start` does. But you can run one single process using `procsd exec` command:

```
deploy@server:~/sample_app$ procsd exec web

=> Booting Puma
=> Rails 5.2.1 application starting in production
=> Run `rails server -h` for more startup options
Puma starting in single mode...
* Version 3.12.0 (ruby 2.3.0-p0), codename: Llamas in Pajamas
* Min threads: 5, max threads: 5
* Environment: production
* Listening on tcp://localhost:2501
Use Ctrl-C to stop
```

`procsd exec` requres all the environment variables defined in `environment` section of `procsd.yml` config file.

Sometimes in development mode you need different environment configuration. For that you can add additional environment section `dev_environment` and require it as well using `--dev` flag, example:

```yaml
app: sample_app
environment:
  PORT: 2501
  RAILS_ENV: production
  RAILS_LOG_TO_STDOUT: true
dev_environment:
  RAILS_ENV: development
  SOME_OTHER_DEV_ENV_VARIABLE: value
```

```
# Run web process with all environment & dev_environment variables included:

deploy@server:~/sample_app$ procsd exec web --dev
```

> In case if `dev_environment` has env variable with the same name like in `environment`, this variable will be rewritten with value from `dev_environment`.


### Nginx integration (with automatic HTTPS)
> Before make sure that you have Nginx installed `sudo apt install nginx` and running `sudo systemctl status nginx`.

If one of your application processes is a web process, you can automatically setup Nginx (reverse proxy) config for it. Why? For example to serve static files (assets, images, and all other files located in `public` folder or another customly defined folder) directly using fast Nginx, rather than application server. Or to enable SSL support (see below).

Add to your procsd.yml `nginx` section with `server_name` option defined:

> If you don't have a domain for an application (or don't need it), you can add server IP instead: `server_name: 159.159.159.159`.

> If your application use multiple domains/subdomains, add all of them separated with space: `server_name: my-domain.com us.my-domain.com uk.my-domain.com`

```yaml
app: sample_app
processes:
  web: bundle exec rails server -p $PORT
  worker: bundle exec sidekiq -e $RAILS_ENV
formation: web=1,worker=2
environment:
  PORT: 2501 # PORT will be used by Nginx to proxy requests from 0.0.0.0:80/443 to 127.0.0.1:PORT (required)
  HOST: localhost # Make sure that your application server in production running on 127.0.0.1, not 0.0.0.0
  RAILS_ENV: production
  RAILS_LOG_TO_STDOUT: true
nginx:
  server_name: my-domain.com
  public_folder_path: public # path is relative to the main project directory, default value is `public`.
```

Configuration is done! Run [procsd create](#create-an-application-export-to-systemd) to create app services with Nginx reverse proxy config:

```
deploy@server:~/sample_app$ procsd create

Creating app units files in the systemd directory (/etc/systemd/system)...
Create: /etc/systemd/system/sample_app-web.1.service
Create: /etc/systemd/system/sample_app-worker.1.service
Create: /etc/systemd/system/sample_app-worker.2.service
Create: /etc/systemd/system/sample_app.target
Reloaded configuraion (daemon-reload)
Created symlink /etc/systemd/system/multi-user.target.wants/sample_app.target → /etc/systemd/system/sample_app.target.
Enabled app target sample_app.target
App services were created and enabled. Run `start` to start them
Creating Nginx config (/etc/nginx/sites-available/sample_app)...
Create: /etc/nginx/sites-available/sample_app
Link Nginx config file to the sites-enabled folder...
Nginx config created and daemon reloaded
```

<details>
  <summary>/etc/nginx/sites-available/sample_app</summary>

```
upstream sample_app {
  server 127.0.0.1:2501;
}

server {
  listen 80;
  listen [::]:80;

  server_name my-domain.com;
  root /home/deploy/sample_app/public;

  location ^~ /assets/ {
    gzip_static on;
    expires max;
    add_header Cache-Control public;
  }

  try_files $uri/index.html $uri @sample_app;
  location @sample_app {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_redirect off;
    proxy_pass http://sample_app;
  }

  client_max_body_size 256M;
  keepalive_timeout 60;
  error_page 500 502 503 504 /500.html;
  error_page 404 /404.html;
  error_page 422 /422.html;
}
```
</details><br>

Everything is done. Start app services (`procsd start`) and go to `http://my-domain.com` where you'll see your application proxying with Nginx.

#### Auto SSL using Certbot

To generate Nginx config with free SSL certificate (from [Let’s Encrypt](https://letsencrypt.org/)) included, you need to install [Certbot](https://certbot.eff.org/) on the remote server first:

```bash
$ sudo apt install software-properties-common
$ sudo add-apt-repository ppa:certbot/certbot
$ sudo apt update
$ sudo apt install certbot python-certbot-nginx
```

> When you install certbot, it automatically setup a cron job (twice per day) to renew expiring certificates ([Automated Renewals](https://certbot.eff.org/docs/using.html#automated-renewals)), so you don't have to worry about renewing certificates manually.

Then update procsd.yml by adding `ssl: true`:

```yml
# ...
nginx:
  server_name: my-domain.com
  ssl: true # added
```

Configuration is done. **Make sure that all domains defined in procsd (nginx.server_name) are pointing to the server IP** where application is hosted. Then run `procsd create` _(you will probably need first run `procsd destroy` if app services already exists)_ as usual:

> By default Certbot obtaining certificate from _Let's Encrypt_ without a contact email. If you want to provide contact email, define env variable `CERTBOT_EMAIL` with your email in the `.env` file.

<details/>
  <summary>Output</summary>

```
deploy@server:~/sample_app$ procsd create

Creating app units files in the systemd directory (/etc/systemd/system)...
Create: /etc/systemd/system/sample_app-web.1.service
Create: /etc/systemd/system/sample_app-worker.1.service
Create: /etc/systemd/system/sample_app-worker.2.service
Create: /etc/systemd/system/sample_app.target
Reloaded configuraion (daemon-reload)
Created symlink /etc/systemd/system/multi-user.target.wants/sample_app.target → /etc/systemd/system/sample_app.target.
Enabled app target sample_app.target
App services were created and enabled. Run `start` to start them
Creating Nginx config (/etc/nginx/sites-available/sample_app)...
Create: /etc/nginx/sites-available/sample_app
Link Nginx config file to the sites-enabled folder...
Nginx config created and daemon reloaded

Execute: sudo certbot --agree-tos --no-eff-email --non-interactive --nginx -d my-domain.com --register-unsafely-without-email
Saving debug log to /var/log/letsencrypt/letsencrypt.log
Plugins selected: Authenticator nginx, Installer nginx
Obtaining a new certificate
Performing the following challenges:
http-01 challenge for my-domain.com
Waiting for verification...
Cleaning up challenges
Deploying Certificate to VirtualHost /etc/nginx/sites-enabled/sample_app
Redirecting all traffic on port 80 to ssl in /etc/nginx/sites-enabled/sample_app

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Congratulations! You have successfully enabled https://my-domain.com

You should test your configuration at:
https://www.ssllabs.com/ssltest/analyze.html?d=my-domain.com
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

IMPORTANT NOTES:
 - Congratulations! Your certificate and chain have been saved at:
   /etc/letsencrypt/live/my-domain.com/fullchain.pem
   Your key file has been saved at:
   /etc/letsencrypt/live/my-domain.com/privkey.pem
   Your cert will expire on 2019-02-17. To obtain a new or tweaked
   version of this certificate in the future, simply run certbot again
   with the "certonly" option. To non-interactively renew *all* of
   your certificates, run "certbot renew"
 - Your account credentials have been saved in your Certbot
   configuration directory at /etc/letsencrypt. You should make a
   secure backup of this folder now. This configuration directory will
   also contain certificates and private keys obtained by Certbot so
   making regular backups of this folder is ideal.
 - If you like Certbot, please consider supporting our work by:

   Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/donate
   Donating to EFF:                    https://eff.org/donate-le

Successfully installed SSL cert using certbot
```
</details><br>

That's it. Start app services (`procsd start`) and go to `https://my-domain.com` where you'll see your application proxying with Nginx and SSL enabled.


<details/>
  <summary>Note about using Cloudflare CDN</summary><br>

If you use Cloudflare CDN, that means the process of obtaining Let's Encrypt SSL Certificate will fail. To fix it, install `python-certbot-dns-cloudflare` package:

```bash
$ sudo apt install certbot python-certbot-dns-cloudflare
```

Read instructions [here how to get Cloudflare API Token and obtain certificates](https://certbot-dns-cloudflare.readthedocs.io/en/stable/). In short,

**1)** Go to https://dash.cloudflare.com/profile/api-tokens and [get your API Token](https://support.cloudflare.com/hc/en-us/articles/200167836-Where-do-I-find-my-Cloudflare-API-key-).

**2)** Create on the server `~/.secrets/certbot/` directory with `cloudflare.ini` file inside:

```bash
$ mkdir -p ~/.secrets/certbot/
$ chmod 0700 ~/.secrets/
$ touch ~/.secrets/certbot/cloudflare.ini
$ chmod 0400 ~/.secrets/certbot/cloudflare.ini
```

**3)** Put inside `cloudflare.ini` file your Cloudflare token:

```bash
$ sudo nano ~/.secrets/certbot/cloudflare.ini
```

```bash
# ~/.secrets/certbot/cloudflare.ini

# Cloudflare API token (example) used by Certbot:
dns_cloudflare_api_token = 0123456789abcdef0123456789abcdef01234567
```

**4)** Obtain certificates for all your domains declared in `procsd.yml` using _certbot-dns-cloudflare_ plugin:

```bash
# Example command for my-domain.com domain:

$ sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini -d my-domain.com
```

**5)** If all went fine, update Nginx application config with new certificates (using certbot command). To get required certbot command type `$ procsd config certbot_command`, then execute it:

```bash
# Example command for my-domain.com domain:

$ sudo certbot --agree-tos --no-eff-email --redirect --non-interactive --nginx -d my-domain.com --register-unsafely-without-email
```

All is done!

</details><br>


## All available commands

```
$ procsd --help

Commands:
  procsd create          # Create and enable app services
  procsd destroy         # Stop, disable and remove app services
  procsd start           # Start app services
  procsd stop            # Stop app services
  procsd restart         # Restart app services
  procsd enable          # Enable app target
  procsd disable         # Disable app target
  procsd logs            # Show app services logs
  procsd status          # Show app services status
  procsd list            # List all app services
  procsd exec            # Run single app process with environment
  procsd config          # Print config files based on current settings. Available types: sudoers, services, certbot_command
  procsd help [COMMAND]  # Describe available commands or one specific command
  procsd --version, -v   # Print the version
```


## Difference with Foreman

[Foreman](http://ddollar.github.io/foreman/) itself designed for _development_ (not production) usage only and doing it great. Yes, Foreman allows to [export](http://ddollar.github.io/foreman/#EXPORTING) Procfile to the Systemd, but that's all. After export you have to manually use `systemctl` and `journalctl` to manage/check exported services. Procsd not only exports application, but provides [simple commands](#all-available-commands) to manage exported target.

* Foreman systemd export uses [dymamic](https://fedoramagazine.org/systemd-template-unit-files/) services templates and as a result generates quite a lot of files/folders in the systemd directory even for a simple application.

* Services generated using Foreman contain [$PORT variable](http://ddollar.github.io/foreman/#PROCFILE) in their names (and it's [undocumented](http://ddollar.github.io/foreman/#SYSTEMD-EXPORT) logic). For example for Procfile and formation `web=1,worker=2` (from example above), exported services with Foreman will be: `sample_app-web@2500.service`, `sample_app-worker@2600.service` and `sample_app-worker@2601.service`. My opinion about this approach: it's complicated. Why is there required PORT variable in the services names? Procsd following one rule: simplicity. For export it uses static service files (that means for each process will be generated it's own service file) and services names have predictable, Heroku-like names.

* Procsd export can provide additional stop/restart commands for each service (see _Notes_ below).

* To delete existing app services from Systemd, there is `procsd destroy` command. It is doing the following: stop services if they are running, delete all required systemd files from systemd directory, and restart systemd (`daemon-reload`). This command especially useful while testing, when you need frequently create/update configuration.


## Notes

* If you want to set environment variables per process, [use format](https://github.com/ddollar/foreman/wiki/Per-Process-Environment-Variables) like Foreman recommends.

* To print commands before execution, provide env variable `VERBOSE=true` before procsd command. Example:

```
deploy@server:~/sample_app$ VERBOSE=true procsd logs -n 3

Execute: journalctl --no-pager --no-hostname --all --output short-iso -n 3 --unit sample_app-*

-- Logs begin at Sun 2018-10-21 00:38:42 +04, end at Sun 2018-11-04 19:17:01 +04. --
2018-11-04T19:11:59+0400 sample_app-worker.2[29907]: 2018-11-04T15:11:59.597Z 29907 TID-gne5aeyuz INFO: Upgrade to Sidekiq Pro for more features and support: http://sidekiq.org
2018-11-04T19:11:59+0400 sample_app-worker.2[29907]: 2018-11-04T15:11:59.597Z 29907 TID-gne5aeyuz INFO: Booting Sidekiq 5.2.2 with redis options {:id=>"Sidekiq-server-PID-29907", :url=>nil}
2018-11-04T19:11:59+0400 sample_app-worker.2[29907]: 2018-11-04T15:11:59.601Z 29907 TID-gne5aeyuz INFO: Starting processing, hit Ctrl-C to stop
```

* You can use extended format of processes commands inside `procsd.yml` to provide additional restart/stop commands for each process:

> All possible options: `ExecStart`, `ExecReload` and `ExecStop`

> If procsd.yml has `processes:` option defined, then content of Procfile will be ignored

```yml
app: sample_app
processes:
  web:
    ExecStart: bundle exec rails server -p $PORT
    ExecReload: bundle exec pumactl phased-restart
  worker: bundle exec sidekiq -e production
```

Why? For example default Ruby on Rails application server [Puma](http://puma.io/) supports [Phased or Rolling restart](https://github.com/puma/puma/blob/master/docs/restart.md#normal-vs-hot-vs-phased-restart) feature. If you provide separate `ExecReload`command for a process, then this command will be called while executing `$ procsd restart` by systemd instead of just killing and starting process again.

* If you use Nginx integration but default Nginx requests timeout (60s) is too small for you, [you can set a custom timeout](https://serverfault.com/a/777753) in the global Nginx config.


## Capistrano integration

https://github.com/vifreefly/capistrano-procsd


## ToDo
* Add `procsd update` command to quickly update changed configuration (application units, nginx config, etc), instead of calling two separate commands (`procsd destroy` and `procsd create`)


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
