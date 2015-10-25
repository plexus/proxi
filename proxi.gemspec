Gem::Specification.new do |gem|
  gem.name        = 'proxi'
  gem.version     = '1.0'
  gem.authors     = [ 'Arne Brasseur' ]
  gem.email       = [ 'arne@arnebrasseur.net' ]
  gem.description = 'TCP and HTTP proxy scripts'
  gem.summary     = gem.description
  gem.homepage    = 'https://github.com/plexus/proxi'
  gem.license     = 'MPL'

  gem.require_paths    = %w[lib]
  gem.files            = `git ls-files`.split $/
  gem.test_files       = gem.files.grep(/^spec/)
  gem.extra_rdoc_files = %w[README.md]

  gem.add_runtime_dependency 'wisper', '> 0'

  gem.add_development_dependency 'rspec', '~> 3.0'
end
