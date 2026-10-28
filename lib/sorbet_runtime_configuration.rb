# typed: false

# Required before bundled gems can evaluate signatures. Keep this outside
# Zeitwerk reloading: Sorbet's process-wide runtime settings cannot be reset.
module SorbetRuntimeConfiguration
  class PolicyError < StandardError; end

  def self.configure!(local:)
    preloaded = defined?(T::Configuration)
    setting = ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"]
    enabled = setting.nil? ? local : ![ "", "0", "false", "off", "no" ].include?(setting.strip.downcase)
    begin
      # Sorbet treats any present value, even "0", as enabled during require.
      ENV.delete("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS") unless enabled
      require "sorbet-runtime"
    ensure
      ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"] = setting
    end

    begin
      if preloaded && !setting.nil? && !enabled
        raise "A preloaded sorbet-runtime already interpreted the disabled checking flag as enabled."
      end

      T::Configuration.default_checked_level = :tests unless ENV.key?("SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL")
      T::Configuration.enable_checking_for_sigs_marked_checked_tests if enabled
    rescue RuntimeError => error
      message = "Sorbet runtime policy could not be applied: #{error.message} " \
        "Load application configuration before evaluating signatures, or configure Sorbet through its environment variables before preloading it."
      raise PolicyError, message unless local

      warn message
    end
  end
end
