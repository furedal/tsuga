# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "tsuga"
  spec.version       = "0.0.2"
  spec.authors       = ["Julien Letessier"]
  spec.email         = ["julien.letessier@gmail.com"]
  spec.description   = %q{Hierarchical Geo Clusterer tuned for Google Maps usage}
  spec.summary       = %q{Hierarchical Geo Clusterer tuned for Google Maps usage}
  spec.homepage      = "https://github.com/furedal/tsuga"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "ruby-progressbar"
  spec.add_runtime_dependency "geokit"

  spec.add_development_dependency "bundler", "~> 2.1"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "guard"
  spec.add_development_dependency "guard-rspec"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-nav"
end
