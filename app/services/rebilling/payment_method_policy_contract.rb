# typed: strict

module Rebilling
  module PaymentMethodPolicyContract
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.returns(T::Boolean) }
    def exhaust_methods_per_step?; end

    sig do
      abstract.params(context: Context, step: RetryStep, preferred_payment_method_id: Object)
        .returns(T.nilable(PaymentMethodSnapshot))
    end
    def select(context, step, preferred_payment_method_id: nil); end
  end
end
