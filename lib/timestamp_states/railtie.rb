# frozen_string_literal: true

require 'rails/railtie'

module TimestampStates
  class Railtie < Rails::Railtie
    initializer 'timestamp_states.insert_into_active_record' do
      ActiveSupport.on_load :active_record do
        include TimestampStates
      end
    end
  end
end
