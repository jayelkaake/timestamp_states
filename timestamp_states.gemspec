# frozen_string_literal: true

require_relative 'lib/timestamp_states/version'

Gem::Specification.new do |spec|
  spec.name = 'timestamp_states'
  spec.version = TimestampStates::VERSION
  spec.authors = ['Jay El-Kaake']
  spec.email = ['najibkaake@gmail.com']

  spec.summary = 'Gives Rails models nice methods for managing columns that define a timestamp that represents a state such as `published_at` => `published?`.'
  spec.homepage = 'https://www.github.com/jayelkaake/timestamp_states'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://www.github.com/jayelkaake/timestamp_states'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  spec.add_dependency 'activesupport', '>= 5'
  spec.add_dependency 'rails', '>= 5'
  spec.add_development_dependency 'anonymous_active_record', '~> 1'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'pry-rails'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'dotenv'
  spec.add_development_dependency 'rspec', '~> 3'
  spec.add_development_dependency 'rubocop', '~> 1.69'
  spec.add_development_dependency 'sqlite3', '>= 1'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
