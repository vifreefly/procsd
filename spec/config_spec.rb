require "spec_helper"
require "procsd/config"
require "tmpdir"

RSpec.describe Procsd::Config do
  around do |example|
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) { example.run }
    end
  end

  describe ".load" do
    it "loads a basic procsd.yml" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        processes:
          web:
            ExecStart: bundle exec puma
      YAML

      config = described_class.load

      expect(config.app).to eq("myapp")
      expect(config.processes).to eq({
        "web" => {
          "commands" => { "ExecStart" => "bundle exec puma" },
          "size" => 1
        }
      })
      expect(config.environment).to eq({})
      expect(config.dev_environment).to eq({})
      expect(config.systemd_dir).to eq("/etc/systemd/system")
      expect(config.nginx).to be_nil
    end

    it "loads processes from Procfile when not defined in procsd.yml" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
      YAML
      File.write("Procfile", <<~PROCFILE)
        web: bundle exec puma
        worker: bundle exec sidekiq
      PROCFILE

      config = described_class.load

      expect(config.processes).to eq({
        "web" => {
          "commands" => { "ExecStart" => "bundle exec puma" },
          "size" => 1
        },
        "worker" => {
          "commands" => { "ExecStart" => "bundle exec sidekiq" },
          "size" => 1
        }
      })
    end

    it "parses formation string to set process sizes" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        formation: web=2,worker=3
        processes:
          web:
            ExecStart: bundle exec puma
          worker:
            ExecStart: bundle exec sidekiq
      YAML

      config = described_class.load

      expect(config.processes["web"]["size"]).to eq(2)
      expect(config.processes["worker"]["size"]).to eq(3)
    end

    it "loads environment and dev_environment" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        environment:
          PORT: 3000
          RAILS_ENV: production
        dev_environment:
          RAILS_ENV: development
        processes:
          web:
            ExecStart: bundle exec puma
      YAML

      config = described_class.load

      expect(config.environment).to eq({ "PORT" => 3000, "RAILS_ENV" => "production" })
      expect(config.dev_environment).to eq({ "RAILS_ENV" => "development" })
    end

    it "loads all process commands (ExecStart, ExecStop, ExecReload, RuntimeMaxSec)" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        processes:
          web:
            ExecStart: bundle exec puma
            ExecStop: bundle exec pumactl stop
            ExecReload: bundle exec pumactl phased-restart
            RuntimeMaxSec: 86400
      YAML

      config = described_class.load

      expect(config.processes["web"]["commands"]).to eq({
        "ExecStart" => "bundle exec puma",
        "ExecStop" => "bundle exec pumactl stop",
        "ExecReload" => "bundle exec pumactl phased-restart",
        "RuntimeMaxSec" => 86400
      })
    end

    it "uses custom systemd_dir when specified" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        systemd_dir: /custom/systemd/path
        processes:
          web:
            ExecStart: bundle exec puma
      YAML

      config = described_class.load

      expect(config.systemd_dir).to eq("/custom/systemd/path")
    end

    it "loads nginx configuration" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        processes:
          web:
            ExecStart: bundle exec puma
        nginx:
          server_name: example.com
          ssl: true
      YAML

      config = described_class.load

      expect(config.nginx).to eq({ "server_name" => "example.com", "ssl" => true })
    end

    it "processes ERB in YAML" do
      ENV["TEST_APP_NAME"] = "dynamic_app"
      File.write("procsd.yml", <<~YAML)
        app: <%= ENV["TEST_APP_NAME"] %>
        processes:
          web:
            ExecStart: bundle exec puma
      YAML

      config = described_class.load

      expect(config.app).to eq("dynamic_app")
    ensure
      ENV.delete("TEST_APP_NAME")
    end

    it "allows custom path argument" do
      File.write("custom_config.yml", <<~YAML)
        app: customapp
        processes:
          web:
            ExecStart: bundle exec puma
      YAML

      config = described_class.load("custom_config.yml")

      expect(config.app).to eq("customapp")
    end

    it "handles simple process definitions (string instead of hash)" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        processes:
          web: bundle exec puma
          worker: bundle exec sidekiq
      YAML

      config = described_class.load

      expect(config.processes).to eq({
        "web" => {
          "commands" => { "ExecStart" => "bundle exec puma" },
          "size" => 1
        },
        "worker" => {
          "commands" => { "ExecStart" => "bundle exec sidekiq" },
          "size" => 1
        }
      })
    end
  end

  describe "error handling" do
    it "raises error when procsd.yml does not exist" do
      expect { described_class.load }.to raise_error(
        Procsd::Config::Error,
        "Config file procsd.yml doesn't exist"
      )
    end

    it "raises error when app name is missing" do
      File.write("procsd.yml", <<~YAML)
        processes:
          web:
            ExecStart: bundle exec puma
      YAML

      expect { described_class.load }.to raise_error(
        Procsd::Config::Error,
        "Missing app name in the procsd.yml file"
      )
    end

    it "raises error when processes not defined and Procfile missing" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
      YAML

      expect { described_class.load }.to raise_error(
        Procsd::Config::Error,
        "Procfile doesn't exists. Define processes in procsd.yml or create Procfile"
      )
    end

    it "raises error when process hash missing ExecStart" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        processes:
          web:
            ExecStop: bundle exec pumactl stop
      YAML

      expect { described_class.load }.to raise_error(
        Procsd::Config::Error,
        "Missing ExecStart command for `web` process"
      )
    end

    it "raises error when YAML is invalid" do
      File.write("procsd.yml", "invalid: yaml: content: [")

      expect { described_class.load }.to raise_error(
        Procsd::Config::Error,
        /Can't read procsd.yml/
      )
    end

    it "raises error when Procfile is invalid" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
      YAML
      File.write("Procfile", "invalid: yaml: [")

      expect { described_class.load }.to raise_error(
        Procsd::Config::Error,
        /Can't read Procfile/
      )
    end
  end

  describe "#to_h" do
    it "returns hash representation of config" do
      File.write("procsd.yml", <<~YAML)
        app: myapp
        processes:
          web:
            ExecStart: bundle exec puma
      YAML

      config = described_class.load

      expect(config.to_h).to eq({
        app: "myapp",
        processes: {
          "web" => {
            "commands" => { "ExecStart" => "bundle exec puma" },
            "size" => 1
          }
        },
        environment: {},
        dev_environment: {},
        systemd_dir: "/etc/systemd/system",
        nginx: nil
      })
    end

    it "includes all config attributes" do
      File.write("procsd.yml", <<~YAML)
        app: fullapp
        formation: web=2
        environment:
          RAILS_ENV: production
        dev_environment:
          RAILS_ENV: development
        systemd_dir: /custom/path
        processes:
          web:
            ExecStart: bundle exec puma
        nginx:
          server_name: example.com
      YAML

      config = described_class.load

      expect(config.to_h).to eq({
        app: "fullapp",
        processes: {
          "web" => {
            "commands" => { "ExecStart" => "bundle exec puma" },
            "size" => 2
          }
        },
        environment: { "RAILS_ENV" => "production" },
        dev_environment: { "RAILS_ENV" => "development" },
        systemd_dir: "/custom/path",
        nginx: { "server_name" => "example.com" }
      })
    end
  end
end
