# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'seize/version'

Gem::Specification.new do |gem|
  gem.name          = "seize"
  gem.version       = Seize::VERSION
  gem.authors       = ["Larry Edelstein"]
  gem.email         = %w(ladlestein@gmail.com)
  gem.description   = %q{A framework for importing data via ActiveRecord}
  gem.summary       = %q{A framework for importing data via ActiveRecord}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = %w(lib)

  gem.add_dependency 'activerecord'

  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'factory_girl'
  gem.add_development_dependency 'sqlite3'
end
