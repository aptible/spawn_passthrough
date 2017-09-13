# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'spawn_passthrough/version'

Gem::Specification.new do |spec|
  spec.name          = 'spawn_passthrough'
  spec.version       = SpawnPassthrough::VERSION
  spec.authors       = ['Thomas Orozco']
  spec.email         = ['thomas@orozco.fr']

  spec.summary       = 'Spawn passthrough processes'
  spec.description   = spec.summary
  spec.homepage      = 'https://github.com/aptible/spawn_passthrough'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'aptible-tasks', '~> 0.5.3'
end
