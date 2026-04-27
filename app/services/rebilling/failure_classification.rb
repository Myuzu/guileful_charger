module Rebilling
  FailureClassification = Data.define(:category,
                                      :network_recommendation,
                                      :retryable,
                                      :requires_credential_refresh,
                                      :customer_action_required)
end
