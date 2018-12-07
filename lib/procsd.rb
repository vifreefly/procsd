require 'dotenv/load'
require 'thor'
require 'erb'
require 'pathname'
require 'yaml'

require 'procsd/version'
require 'procsd/generator'
require 'procsd/generators/units_generator'
require 'procsd/generators/sudoers_generator'
require 'procsd/generators/nginx_generator'

module Procsd
  DEFAULT_SYSTEMD_DIR = "/etc/systemd/system".freeze
  SUDOERS_DIR = "/etc/sudoers.d".freeze
  NGINX_DIR = "/etc/nginx".freeze
end
