module Rebilling
  Plan = Data.define(:step_key,
                     :payment_method_id,
                     :attempt_number,
                     :amount_cents,
                     :retry_at,
                     :earliest_retry_at,
                     :latest_retry_at,
                     :retry_strategy,
                     :idempotency_key,
                     :strategy_version,
                     :source_attempt_id)
end
