# frozen_string_literal: true

require 'timestamp_states'
require 'anonymous_active_record'

require 'dotenv/load'

if ENV['DEV_MODE']
  require 'pry'
  require 'pry-rails'
  require 'pry-byebug'
end


RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.expose_dsl_globally = true
end
