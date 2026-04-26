class PauseSubscriptionService < ApplicationService
  param :subscription
  option :reason, optional: true

  input_schema do
    optional(:reason).maybe(:string)
  end

  def call
    Subscription.transaction do
      subscription.lock!

      return Success(subscription) if subscription.paused?
      return subscription_failure(:already_cancelled, subscription) if subscription.cancelled?

      subscription.pause!(reason)
      destroy_unstarted_current_period_draft_invoices
      enqueue_subscription_paused

      Success(subscription)
    end
  end

  private

  def destroy_unstarted_current_period_draft_invoices
    subscription.invoices
                .draft
                .where(billing_period_start: subscription.current_period_start,
                       billing_period_end:   subscription.current_period_end,
                       payment_attempts_count: 0)
                .delete_all
  end

  def enqueue_subscription_paused
    OutboxMessage.enqueue!(topic:             "subscription.paused",
                           payload:           lifecycle_payload,
                           aggregate:         subscription,
                           aggregate_version: subscription.state_version)
  end

  def lifecycle_payload
    subscription.lifecycle_payload(reason: reason)
  end
end
