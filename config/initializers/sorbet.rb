require_relative "../../lib/sorbet_runtime_policy"

SorbetRuntimePolicy.configure(production: Rails.env.production?, logger: Rails.logger)
