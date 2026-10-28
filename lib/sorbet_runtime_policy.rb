# Keep gradual signatures observable without turning annotation mistakes into
# failed billing operations. Never log inspected arguments or return values.
module SorbetRuntimePolicy
  def self.configure(production:, logger:)
    return unless production

    T::Configuration.call_validation_error_handler = lambda do |signature, options|
      logger.error("Sorbet signature mismatch: #{signature.method.owner}##{signature.method.name} (#{options[:kind]})")
    end
  end
end
