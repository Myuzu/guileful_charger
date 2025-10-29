source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# A system for processing messages from RabbitMQ
gem "hutch", "~> 1.3.0"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Integration of RubyMoney - Money with Rails
gem "money-rails", "~> 1.15.0"

# State machines for Ruby classes
gem "aasm", "~> 5.5.2"

gem "csv"

# dry-rb gems
gem "dry-struct"
gem "dry-types"
gem "dry-initializer"
gem "dry-monads"

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development do
  # The Ruby LSP is an implementation of the language server protocol
  gem "ruby-lsp"

  # A Ruby Gem that adds annotations to your Rails models and route files
  gem "annotaterb"

  # Guard::RSpec automatically run your specs (much like autotest)
  gem "guard-rspec", require: false

  # Git hooks management
  gem "overcommit"
end

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Factory Bot ♥ Rails
  gem "factory_bot_rails", "~> 6.5.1"

  # A library for generating fake data such as names, addresses, and phone numbers.
  gem "faker", "~> 3.5.2"

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "rubocop-performance", require: false
  gem "rubocop-rspec", require: false

  # rspec-rails
  gem "rspec-rails"
  gem "shoulda-matchers", "~> 6.5"
end
