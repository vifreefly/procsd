# CHANGELOG
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
