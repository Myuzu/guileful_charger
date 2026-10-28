# typed: false

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# Set these before any bundled gem can load sorbet-runtime or evaluate a sig.
ENV["SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL"] ||= "tests"

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
