require 'dotenv/load'
require 'thor'
require 'procsd/version'

module Procsd
  DEFAULT_SYSTEMD_DIR = "/etc/systemd/system".freeze
  SUDOERS_DIR = "/etc/sudoers.d".freeze
end
