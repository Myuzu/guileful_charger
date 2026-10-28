# typed: false

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
# Configure fresh Rails processes before bundled gems evaluate signatures.
# Tools such as Tapioca that already loaded Sorbet retain their own policy.
unless defined?(T::Configuration)
  checking_setting = ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"]
  checking_enabled = checking_setting.nil? ? Rails.env.local? : ![ "", "0", "false", "off", "no" ].include?(checking_setting.strip.downcase)
  begin
    # Sorbet interprets even "0" as enabled. Normalize only during its require,
    # then restore operator input so no generated settings leak to subprocesses.
    ENV.delete("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS") unless checking_enabled
    require "sorbet-runtime"
  ensure
    ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"] = checking_setting
  end
  T::Configuration.default_checked_level = :tests unless ENV.key?("SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL")
  T::Configuration.enable_checking_for_sigs_marked_checked_tests if checking_enabled
end
Bundler.require(*Rails.groups)

module GuilefulCharger
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks dry_type_catalog.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    # PostgreSQL partitioning and pg_partman retention config are migration-owned.
    # Rails schema dumps do not preserve pg_partman's extension-managed config data.
    config.active_record.schema_format = :sql
    config.active_record.dump_schema_after_migration = false

    config.generators do |generate|
      generate.orm :active_record, primary_key_type: :uuid
    end
  end
end
