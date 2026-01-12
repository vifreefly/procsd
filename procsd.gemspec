
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "procsd/version"

Gem::Specification.new do |spec|
  spec.name          = "procsd"
  spec.version       = Procsd::VERSION
  spec.authors       = ["Victor Afanasev"]
  spec.email         = ["vicfreefly@gmail.com"]

  spec.summary       = "Manage your application processes in production hassle-free like Heroku CLI with Procfile and Systemd"
  spec.homepage      = "https://github.com/vifreefly/procsd"
  spec.license       = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.bindir        = "exe"
  spec.executables   = "procsd"
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.2.0"

  spec.add_dependency "thor"
  spec.add_dependency "dotenv"

  spec.add_development_dependency "bundler", ">= 1.16"
  spec.add_development_dependency "rake", ">= 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "simplecov"
end
