# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "json-rpc-1-1/version"

Gem::Specification.new do |s|
  s.name        = "jsonrpc"
  s.version     = JsonRPC::VERSION
  s.authors     = ["Peter Bengtson"]
  s.email       = ["peter@peterbengtson.com"]
  s.homepage    = "https://github.com/PeterBengtson/json-rpc-1-1"
  s.summary     = %q{A Rails plugin implementing the JSON-RPC 1.1 protocol for remote procedure calls}
  s.description = %q{Implementation consists of two parts: a service side and a client side. The server part is written specifically for Ruby on Rails, but the client does not really require Rails. A Rails application may choose to act as a service provider, as a client, or both.}

  s.rubyforge_project = "json-rpc-1-1"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
