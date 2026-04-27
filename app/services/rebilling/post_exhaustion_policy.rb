module Rebilling
  class PostExhaustionPolicy
    DEFAULT_ACTION = :pause_subscription

    def handle(_invoice, _exhaustion_reason)
      DEFAULT_ACTION
    end
  end
end
