# CHANGELOG
## 0.6.0
* **Breaking change:** Require Ruby >= 3.2.0 (dropping support for EOL versions)
* Fix: Use YAML.safe_load instead of deprecated YAML.load
* Fix: Use new `trim_mode` keyword argument for ERB.new
* Change: Relax bundler/rake version constraints to allow modern versions
* Add: Test coverage for generator output

Thanks to [@botandrose](https://github.com/botandrose) (Micah Geisel) for contributions!

## 0.5.5
* Add: Allow to start/stop/restart particular service in the app target (example: `$ procsd start web`)
* Add: RuntimeMaxSec option for process

## 0.5.4
* Add: information how to use SSL integration with Cloudflare CDN enabled
* Add: procsd config certbot_command command

## 0.5.3
* Fix: procsd config sudoers command
* Add: procsd config services command

## 0.5.2
* Fix: use uniq app name in Nginx config files
* Add: custom option public_folder_path (Nginx)
* Add: --dev option for exec command (to require dev_environment in development mode)

## 0.5.1
* Fix bug `uninitialized constant Procsd::Generator::Pathname`, thanks to @koppen

## 0.5.0
* **Breaking change:** Changed the way how to define SSL option for Ngnix configuration in procsd.yml (and by default contact email is not required anymore)

Was:
```yml
nginx:
  server_name: my-domain.com
  certbot:
    email: some@email.com
```

Now:
```yml
nginx:
  server_name: my-domain.com
  ssl: true
```

If you want to provide email for Let's Encrypt, make sure that you have env variable CERTBOT_EMAIL=my_email while executing `$ procsd create`. You can put CERTBOT_EMAIL variable to the application's `.env` file (procsd will read this file if it exists) or simply call create command this way: `CERTBOT_EMAIL=my_email procsd create`.

* Change SyslogIdentifier for services from %n to %p

## 0.4.0
* **Breaking change:** commands in extended processes syntax were renamed from start/restart/stop to ExecStart/ExecReload/ExecStop:

Was:
```yml
processes:
  web:
    start: bundle exec rails server -p $PORT
    restart: bundle exec pumactl phased-restart
```

Now:
```yml
processes:
  web:
    ExecStart: bundle exec rails server -p $PORT
    ExecReload: bundle exec pumactl phased-restart
```

* Added new command `exec` to run one of the defined processes (for development purposes). Example: `$ procsd exec web`.
* Added Nginx support with auto-ssl (using Certbot)

## 0.3.0
* **Breaking change:** `.procsd.yml` renamed to `procsd.yml` (without dot)
* **Breaking change:** `environment` option in the procsd.yml now has hash format, not array:

Was:
```
environment:
  - PORT=2501
  - RAILS_ENV=production
  - RAILS_LOG_TO_STDOUT=true
```

Now:
```
environment:
  PORT: 2501
  RAILS_ENV: production
  RAILS_LOG_TO_STDOUT: true
```

* Add `--or-restart` option for `create` command
* Options `--user`, `--path` and `--dir` for `create` command are not required anymore (but still can be provided)
* Add new `config` command (currently it can print only content for sudoers file: `$ procsd config sudoers`)
* Add `--add-to-sudoers` option for `create` command to automatically add `/bin/systemctl start/stop/restart app_name.target` commands to sudoers `/etc/sudoers.d/app_name` file (passwordless sudo)


## 0.2.0
* Allow to use erb inside .procsd.yml
* Add dotenv support
* Add VERBOSE option to print commands before execution
* Implement option to provide restart/stop commands in the Procfile (extended syntax)
* Add list command
*  Add sudo to `status` and `logs` commands to show system messages as well
* Add --short option to the `status` command
