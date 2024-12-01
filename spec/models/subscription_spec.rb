# == Schema Information
#
# Table name: subscriptions
#
#  id                      :uuid             not null, primary key
#  amount_cents            :integer          default(0), not null
#  current_period_end      :datetime         not null
#  current_period_start    :datetime         not null
#  last_payment_at         :datetime
#  next_payment_attempt_at :datetime
#  retry_count             :integer          default(0), not null
#  status                  :enum             default(NULL), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  customer_id             :uuid             not null
#
# Indexes
#
#  index_subscriptions_on_current_period_end                  (current_period_end)
#  index_subscriptions_on_customer_id                         (customer_id)
#  index_subscriptions_on_status_and_next_payment_attempt_at  (status,next_payment_attempt_at)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#
require "rails_helper"

RSpec.describe Subscription, type: :model do
  describe "#calculate_payment_amount" do
    context "with Subscription beeing cancelled" do
      let(:subscription) { FactoryBot.create(:subscription, status: :cancelled) }

      it "returns full subscription amount" do
        expect(subscription.calculate_payment_amount).to eq(Money.new(1200))
      end
    end

    context "with active Subscription beeing not paid" do
      let(:subscription) { FactoryBot.create(:subscription, status: :active) }

      it "returns full subscription amount" do
        expect(subscription.calculate_payment_amount).to eq(Money.new(1200))
      end
    end

    context "with Subscription beeing paid 25%" do
      let(:subscription) { FactoryBot.create(:subscription, status: :past_due) }

      it "returns full subscription amount" do
        # subscription.payment_attempts

        expect(subscription.calculate_payment_amount).to eq(Money.new(300))
      end
    end

    context "with Subscription beeing paid 50%"
    context "with Subscription beeing paid 75%"
  end
end
