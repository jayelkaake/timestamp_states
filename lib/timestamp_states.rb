# frozen_string_literal: true

require_relative 'timestamp_states/version'
require 'timestamp_states/railtie' if defined?(Rails::Railtie)
require 'active_support/concern'

module TimestampStates
  extend ActiveSupport::Concern

  class Error < StandardError; end

  included do
    scope :with_timestamp_state_within, lambda { |column, dates, timezone = 'EDT'|
      dates = Array(dates).join.split(/\s*(,|to)\s*/i).grep_v(/\s*(,|to)\s*/i).map(&:strip)
      times = dates.map { |date| Time.parse("#{date} 00:00:00 #{timezone}") }
      times << (times.first + 1.day) if times.size == 1
      where(column => times.first..times.last)
    }

    scope :with_timestamp_state, lambda { |column, range|
      if range.is_a?(Range) || range.is_a?(Time) || range.is_a?(Date)
        where(column => range)
      else
        with_timestamp_state_within(column, range)
      end
    }

    around_save :around_timestamp_state_save
  end

  module ClassMethods
    def timestamp_state_configs = @timestamp_state_configs

    def add_timestamp_state_config(column)
      @timestamp_state_configs ||= {}
      @timestamp_state_configs[column] ||= {}
      yield(@timestamp_state_configs[column])
    end

    def timestamp_state_config_aliases = @timestamp_state_config_aliases

    ##
    # @param [Symbol] column The name of the column to define timestamp states for. Example: `:published_at`, `:archived_at`, etc
    # @option options [Hash] :words
    # @option options [Symbol] :words[:past] The word to use for the past tense of the timestamp state
    # @option options [Symbol] :words[:action] The word to use for the action of the timestamp state
    # @option options [Boolean] :define_scopes Whether or not to define scopes for the timestamp state
    def timestamp_state(column, words: {}, define_scopes: true, aliases: [])
      add_timestamp_state_config(column) do |config|
        config[:words] = config[:words].to_h.merge(words)
        config[:words][:past] ||= column.to_s.gsub(/_at$/, '').to_sym
        config[:words][:action] ||= column.to_s
                                          .sub(/_at$/, '')
                                          .sub(/d$/, '')
                                          .sub(/([^tvklur])e$/, '\1') # spellr:disable-line
                                          .sub(/lle$/, 'l')
                                          .sub(/tte$/, 't')
                                          .sub(/pp$/, 'p').to_sym
        config[:words][:action] = config[:words][:past].to_s.gsub(/ed$/, '').to_sym if config[:words][:past].to_s =~ /^(install|fail)ed$/ # Weird edge case I guess
        config[:words][:past_not] ||= "not_#{config[:words][:past]}".to_sym
        config[:words][:not_action] ||= "un#{config[:words][:action]}".to_sym

        action_word = config[:words][:action]
        not_action_word = config[:words][:not_action]
        past_word = config[:words][:past]
        past_not_word = config[:words][:past_not]

        if define_scopes
          scope past_word, -> { where.not(column => nil) }
          scope past_not_word, -> { where(column => nil) }
          scope column, ->(range) { with_timestamp_state(column, range) }
        end

        define_model_callbacks action_word, not_action_word

        Array(aliases).each { |alias_name| alias_timestamp_state(column, alias_name, define_scopes: define_scopes) }
      end
    end

    def timestamp_states(*columns, **options)
      return timestamp_state_configs if columns.empty?

      columns.each { |column| timestamp_state(column, **options) }
    end

    def alias_timestamp_state(column, alias_name, define_scopes: true)
      @timestamp_state_config_aliases ||= {}
      @timestamp_state_config_aliases[column] ||= []
      @timestamp_state_config_aliases[column] << alias_name unless @timestamp_state_config_aliases[column].include?(alias_name)

      alias_attribute alias_name, column # ensure the attribute is aliased as well

      has_timestamp_state(alias_name, define_scopes: define_scopes)
    end
  end

  def method_missing(method_name, *args, &block)
    self.class.timestamp_state_configs.to_h.each do |column, options|
      return timestamp_state?(column) if method_name.to_s == "#{options[:words][:past]}?" || method_name.to_s == options[:words][:past].to_s
      return !timestamp_state?(column) if method_name.to_s == "#{options[:words][:past_not]}?" || method_name.to_s == options[:words][:past_not].to_s
      return touch_timestamp_state(column) if method_name.to_s == options[:words][:action].to_s
      return unset_timestamp_state(column) if method_name.to_s == options[:words][:not_action].to_s
      return touch_timestamp_state!(column) if method_name.to_s == "#{options[:words][:action]}!"
      return unset_timestamp_state!(column) if method_name.to_s == "#{options[:words][:not_action]}!"
      return set_timestamp_state(column, args.first) if method_name.to_s == "#{options[:words][:past]}="
      return set_timestamp_state(column, !args.first) if method_name.to_s == "#{options[:words][:past_not]}="
    end

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    self.class.timestamp_state_configs.to_h.each_value do |options|
      return true if method_name.to_s == "#{options[:words][:past]}?" || method_name.to_s == options[:words][:past].to_s
      return true if method_name.to_s == options[:words][:action].to_s || method_name.to_s == "#{options[:words][:action]}!"
      return true if method_name.to_s == options[:words][:not_action].to_s || method_name.to_s == "#{options[:words][:not_action]}!"
      return true if method_name.to_s == "#{options[:words][:past]}=" || method_name.to_s == "#{options[:words][:past_not]}="
    end

    super
  end

  private

  def timestamp_state_configs
    self.class.timestamp_state_configs.to_h.map do |column, options|
      timestamp_state?(column) ? options[:past] : nil
    end.compact
  end

  def around_timestamp_state_save(&block)
    callbacks = [block]

    # What we're doing here is nesting each callback inside the next callback, then ending by
    # calling the pram block to trigger the actual save.
    self.class.timestamp_state_configs.to_h.each do |column, options|
      callbacks.unshift(-> { run_callbacks(options[:words][:action]) { callbacks.shift.try(:call) } }) if !timestamp_state_previously_set?(column) && timestamp_state?(column)
    end.compact

    callbacks.shift.try(:call)
  end

  def timestamp_state_previously_set?(column)
    previous_changes[column].to_a.first.present?
  end

  def set_timestamp_state(column, value)
    send("#{column}=", determine_timestamp_state_value(value))
  end

  def touch_timestamp_state(column)
    send("#{column}=", Time.now.utc)
  end

  def touch_timestamp_state!(column)
    touch_timestamp_state(column)
    save!
  end

  def unset_timestamp_state(column)
    send("#{column}=", nil)
  end

  def unset_timestamp_state!(column)
    unset_timestamp_state(column)
    save!
  end

  def timestamp_state?(column)
    send(column).present?
  end

  ##
  # @param [NilClass, String, Time, Numeric, Boolean] value
  # @return [Time, NilClass]
  def determine_timestamp_state_value(value)
    if [true, false, 'true', 'false', 0, 1, '0', '1', nil, 'null'].include?(value)
      value.to_bool ? Time.now.utc : nil
    else
      Time.zone.parse(value.to_s)
    end
  end
end
