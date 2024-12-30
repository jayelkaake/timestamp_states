# frozen_string_literal: true

require_relative "timestamp_states/version"
require "active_support/concern"

module TimestampStates
  extend ActiveSupport::Concern

  class Error < StandardError; end

  included do
    class_attribute :timestamp_states, default: {}
    class_attribute :timestamp_state_aliases, default: {}

    scope :with_timestamp_state_within, -> (column, dates, timezone = "EDT") {
      dates = Array(dates).join.split(/\s*(,|to)\s*/i).grep_v(/\s*(,|to)\s*/i).map(&:strip)
      times = dates.map { |date| Time.parse("#{ date } 00:00:00 #{ timezone }") }
      times << (times.first + 1.day) if times.size == 1
      where(column => times.first..times.last)
    }

    scope :with_timestamp_state, -> (column, range) {
      if range.is_a?(Range) || range.is_a?(Time) || range.is_a?(Date)
        where(column => range)
      else
        with_timestamp_state_within(column, range)
      end
    }

    around_save :around_timestamp_state_save
  end

  module ClassMethods
    ##
    # @param [Symbol] column The name of the column to define timestamp states for. Example: `:published_at`, `:archived_at`, etc
    # @option options [Hash] :words
    # @option options [Symbol] :words[:past] The word to use for the past tense of the timestamp state
    # @option options [Symbol] :words[:action] The word to use for the action of the timestamp state
    # @option options [Boolean] :define_scopes Whether or not to define scopes for the timestamp state
    def timestamp_state(column, words: {}, define_scopes: true, aliases: [])
      self.timestamp_states[column] ||= {}
      self.timestamp_states[column][:words] = self.timestamp_states[column][:words].to_h.merge(words)
      self.timestamp_states[column][:words][:past] ||= column.to_s.gsub(/_at$/, '').to_sym
      self.timestamp_states[column][:words][:action] ||= column.to_s
                                                               .sub(/_at$/, '')
                                                               .sub(/d$/, '')
                                                               .sub(/([^tvklur])e$/, '\1') # spellr:disable-line
                                                               .sub(/lle$/, 'l')
                                                               .sub(/tte$/, 't')
                                                               .sub(/pp$/, 'p').to_sym
      self.timestamp_states[column][:words][:action] = "install" if self.timestamp_states[column][:words][:past] == :installed # Weird edge case I guess
      self.timestamp_states[column][:words][:past_not] ||= "not_#{ self.timestamp_states[column][:words][:past] }".to_sym
      self.timestamp_states[column][:words][:not_action] ||= "un#{ self.timestamp_states[column][:words][:action] }".to_sym

      action_word = self.timestamp_states[column][:words][:action]
      not_action_word = self.timestamp_states[column][:words][:not_action]
      past_word = self.timestamp_states[column][:words][:past]
      past_not_word = self.timestamp_states[column][:words][:past_not]

      if define_scopes
        scope past_word, -> { where.not(column => nil) }
        scope past_not_word, -> { where(column => nil) }
        scope column, -> (range) { with_timestamp_state(column, range) }
      end

      define_model_callbacks action_word, not_action_word

      Array(aliases).each { |alias_name| alias_timestamp_state(column, alias_name, define_scopes: define_scopes) }
    end

    def alias_timestamp_state(column, alias_name, define_scopes: true)
      self.timestamp_state_aliases[column] ||= []
      self.timestamp_state_aliases[column] << alias_name
      self.timestamp_state_aliases[column].uniq!

      alias_attribute alias_name, column # ensure the attribute is aliased as well

      has_timestamp_state(alias_name, define_scopes: define_scopes)
    end
  end

  def method_missing(method_name, *args, &block)
    self.class.timestamp_states.each do |column, options|
      return timestamp_state?(column) if method_name.to_s == "#{ options[:words][:past] }?" || method_name.to_s == options[:words][:past].to_s
      return !timestamp_state?(column) if method_name.to_s == "#{ options[:words][:past_not] }?" || method_name.to_s == options[:words][:past_not].to_s
      return touch_timestamp_state(column) if method_name.to_s == options[:words][:action].to_s
      return unset_timestamp_state(column) if method_name.to_s == options[:words][:not_action].to_s
      return touch_timestamp_state!(column) if method_name.to_s == "#{ options[:words][:action] }!"
      return unset_timestamp_state!(column) if method_name.to_s == "#{ options[:words][:not_action] }!"
      return set_timestamp_state(column, args.first) if method_name.to_s == "#{ options[:words][:past] }="
      return set_timestamp_state(column, !args.first) if method_name.to_s == "#{ options[:words][:past_not] }="
    end

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    self.class.timestamp_states.each_value do |options|
      return true if method_name.to_s == "#{ options[:words][:past] }?" || method_name.to_s == options[:words][:past].to_s
      return true if method_name.to_s == options[:words][:action].to_s || method_name.to_s == "#{ options[:words][:action] }!"
      return true if method_name.to_s == options[:words][:not_action].to_s || method_name.to_s == "#{ options[:words][:not_action] }!"
      return true if method_name.to_s == "#{ options[:words][:past] }=" || method_name.to_s == "#{ options[:words][:past_not] }="
    end

    super
  end

  private

  def timestamp_states
    self.class.timestamp_states.map do |column, options|
      timestamp_state?(column) ? options[:past] : nil
    end.compact
  end

  def around_timestamp_state_save(&block)
    callbacks = [block]

    # What we're doing here is nesting each callback inside the next callback, then ending by
    # calling the pram block to trigger the actual save.
    self.class.timestamp_states.each do |column, options|
      if !timestamp_state_previously_set?(column) && timestamp_state?(column)
        callbacks.unshift(-> { run_callbacks(options[:words][:action]) { callbacks.shift.try(:call) } })
      end
    end.compact

    callbacks.shift.try(:call)
  end

  def timestamp_state_previously_set?(column)
    previous_changes[column].to_a.first.present?
  end

  def set_timestamp_state(column, value)
    send("#{ column }=", determine_timestamp_state_value(value))
  end

  def touch_timestamp_state(column)
    send("#{ column }=", Time.now.utc)
  end

  def touch_timestamp_state!(column)
    touch_timestamp_state(column)
    save!
  end

  def unset_timestamp_state(column)
    send("#{ column }=", nil)
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
