# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "json-rpc-1-1/version"

Gem::Specification.new do |s|
  s.name        = "json-rpc-1-1"
  s.version     = Json::Rpc::1::1::VERSION
  s.authors     = ["Glenn Francis Murray"]
  s.email       = ["glenn@metonymous.com"]
  s.homepage    = ""
  s.summary     = %q{TODO: Write a gem summary}
  s.description = %q{TODO: Write a gem description}

  s.rubyforge_project = "json-rpc-1-1"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
