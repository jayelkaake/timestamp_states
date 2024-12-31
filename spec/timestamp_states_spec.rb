# frozen_string_literal: true

require 'spec_helper'

describe TimestampStates do
  before do
    # Establish connection to an in-memory SQLite database
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: ':memory:'
    )

    # Define a temporary model for testing
    class ExampleModel < ActiveRecord::Base # rubocop:disable Lint/ConstantDefinitionInBlock
      self.table_name = 'example_models'
      include TimestampStates
      timestamp_state :installed_at
    end

    # Create the test table
    ActiveRecord::Schema.define do
      create_table :example_models, force: true do |t|
        t.datetime :installed_at
      end
    end
  end

  subject(:model) { ExampleModel.create(installed_at: installed_at) }
  let(:installed_at) { nil }

  describe 'scopes' do
    describe '#timestamp_state_within' do
      it 'returns records with a timestamp state within the given range' do
        expect(model.class.installed_at('2023-10-28 to 2023-11-29')).to be_none

        model.update(installed_at: Time.parse('2023-11-01'))

        expect(model.class.installed_at('2023-10-28 to 2023-11-29')).to include(model)
      end
    end

    describe '#timestamp_state' do
      it 'returns the expected models within the date range' do
        expect(ExampleModel.all.installed_at(1.day.ago..1.day.from_now)).to be_none

        model.touch(:installed_at)

        expect(ExampleModel.all.installed_at(1.day.ago..1.day.from_now)).to include(model)
        expect(ExampleModel.all.installed).to include(model)
        expect(ExampleModel.all.not_installed).to be_none

        model.update(installed_at: 2.days.ago)

        expect(ExampleModel.all.installed_at(1.day.ago..1.day.from_now)).to be_none
        expect(ExampleModel.all.installed).to include(model)
        expect(ExampleModel.all.not_installed).to be_none

        model.update(installed_at: nil)

        expect(ExampleModel.all.installed_at(1.day.ago..1.day.from_now)).to be_none
        expect(ExampleModel.all.installed).to be_none
        expect(ExampleModel.all.not_installed).to include(model)
      end
    end

    describe '#set_timestamp_state' do
      it 'returns the expected models within the date range' do
        expect do
          model.install
        end.to change(model, :installed_at)
                 .from(nil)
                 .and change(model, :installed?)
                        .from(false)
                        .to(true)
                        .and change(model,
                                    :not_installed?)
                               .from(true)
                               .to(false)

        expect(model.installed_at).to be_within(1.second).of(Time.now.utc)

        expect do
          model.uninstall
        end.to change(model,
                      :installed_at).to(nil)
                                    .and change(model, :installed?)
                                           .from(true)
                                           .to(false)
                                           .and change(model, :not_installed?)
                                                  .from(false)
                                                  .to(true)
      end
    end
  end

  describe 'callbacks' do
    describe 'after_timestamp_change' do
      it 'triggers the callbacks once' do
        reactions = {}
        model.singleton_class.before_install -> { reactions[:before] = reactions[:before].to_i + 1 }
        model.singleton_class.after_install -> { reactions[:after] = reactions[:after].to_i + 1 }
        model.singleton_class.around_install lambda { |_, process|
          reactions[:before_around] = reactions[:before_around].to_i + 1
          process.call
          reactions[:after_around] = reactions[:after_around].to_i + 1
        }

        expect do
          model.install!
        end.to change {
          reactions[:after]
        }.from(nil).to(1).and change {
          reactions[:before]
        }.from(nil).to(1).and change {
          reactions[:before_around]
        }.from(nil).to(1).and change {
          reactions[:after_around]
        }.from(nil).to(1)
      end
    end
  end

  describe 'magic instance methods' do
    describe '#touch_timestamp_state!' do
      it 'sets the timestamp state to now' do
        expect { model.install! }.to change(model, :installed_at).from(nil).to be_within(1.second).of Time.now.utc
      end
    end

    describe '#timestamp_state?' do
      it 'sets the timestamp state to now' do
        expect { model.install! }.to change(model, :installed?).from(false).to(true)
      end
    end
  end
end
