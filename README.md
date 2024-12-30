# TimestampState

This gem adds methods and scopes to your Rails models to easily interact with state flags that are stored as timestamp (`datetime`) values.

For example, if you have a `published_at` column in your `Product` model, then this gem adds things like `product.published?` and `product.publish!` that get and set the published_at value respectively.

## Installation
Install the gem and add to the application's Gemfile by executing:

    $ bundle add timestamp_states

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install timestamp_states

## Usage

Just add a `_at` column to your DB and `timestamp_state :column_name` to your model and get a bunch of magic methods.

Example:
`bundle exec rails g migration AddPublishedAtToProducts published_at:datetime && bundle exec rails db:migrate`
then add `timestamp_state :published_at` to your Product model


### Model methods:
```ruby
    Product.first.published? # true of false
    Product.first.publish # sets value to now
    Product.first.publish! # sets value to now and saves
    Product.first.timestamp_states # returns [:published]
```

### Scopes:
```ruby
    Product.published # gets all published products
    Product.not_published # gets all unpublished products
    Product.published_at(1.day.ago..Time.now.utc) # gets all published products within the last day
    Product.published_at("2023-10-28 to 2023-11-29") # gets all published products within that date range (useful for filters with Flatpickr JS)
```

### Callbacks:
```ruby
after_publish :do_something # runs the callback after the product is published (after the timestamp is set AND saved)
before_publish :do_something # runs the callback before the product is published (after the timestamp is set AND saved)
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/timestamp_states. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/timestamp_states/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the TimestampState project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/timestamp_states/blob/master/CODE_OF_CONDUCT.md).
