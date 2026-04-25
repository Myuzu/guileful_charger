# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
# == Schema Information
#
# Table name: subscriptions
#
#  id                   :uuid             not null, primary key
#  active_at            :datetime
#  amount_cents         :integer          default(0), not null
#  cancellation_reason  :text
#  cancelled_at         :datetime
#  current_period_end   :datetime         not null
#  current_period_start :datetime         not null
#  pause_reason         :text
#  paused_at            :datetime
#  resume_reason        :text
#  resumed_at           :datetime
#  state_version        :integer          default(0), not null
#  status               :enum             default(NULL), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#
# Indexes
#
#  index_subscriptions_on_customer_id                    (customer_id)
#  index_subscriptions_on_status_and_current_period_end  (status,current_period_end)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#
require "rails_helper"

RSpec.describe Subscription, type: :model do
  it { is_expected.to belong_to(:customer) }

  describe "state machine" do
    it "starts active" do
      subscription = FactoryBot.create(:subscription)

      expect(subscription).to be_active
    end

    it "pauses an active subscription" do
      subscription = FactoryBot.create(:subscription)

      subscription.pause!("customer requested pause")

      expect(subscription).to be_paused
    end

    it "resumes a paused subscription" do
      subscription = FactoryBot.create(:subscription, :paused)

      subscription.resume!("customer requested resume")

      expect(subscription).to be_active
    end

    it "cancels an active subscription" do
      subscription = FactoryBot.create(:subscription)

      subscription.cancel!("customer requested cancellation")

      expect(subscription).to be_cancelled
    end

    it "cancels a paused subscription" do
      subscription = FactoryBot.create(:subscription, :paused)

      subscription.cancel!("customer requested cancellation")

      expect(subscription).to be_cancelled
    end

    it "does not resume a cancelled subscription" do
      subscription = FactoryBot.create(:subscription, :cancelled)

      expect { subscription.resume! }.to raise_error(AASM::InvalidTransition)
    end
  end

  describe "pause metadata" do
    it "sets paused metadata and increments the state version" do
      subscription = FactoryBot.create(:subscription)

      expect {
        subscription.pause!("customer requested pause")
      }.to change(subscription, :state_version).by(1)

      expect(subscription.paused_at).to be_present
      expect(subscription.pause_reason).to eq("customer requested pause")
    end
  end

  describe "resume metadata" do
    it "sets resume metadata and extends the current period by the pause duration" do
      now = Time.current
      paused_at = 2.days.ago
      current_period_end = 1.week.from_now
      subscription = FactoryBot.create(:subscription, :paused,
                                       paused_at:          paused_at,
                                       current_period_end: current_period_end)

      allow(Time).to receive(:current).and_return(now)

      expect {
        subscription.resume!("customer requested resume")
      }.to change(subscription, :state_version).by(1)

      expect(subscription.active_at).to be_within(1.second).of(now)
      expect(subscription.resumed_at).to be_within(1.second).of(now)
      expect(subscription.resume_reason).to eq("customer requested resume")
      expect(subscription.current_period_end.to_i).to eq((current_period_end + (now - paused_at)).to_i)
    end
  end

  describe "cancellation metadata" do
    it "sets cancellation metadata and increments the state version" do
      subscription = FactoryBot.create(:subscription)

      expect {
        subscription.cancel!("customer requested cancellation")
      }.to change(subscription, :state_version).by(1)

      expect(subscription.cancelled_at).to be_present
      expect(subscription.cancellation_reason).to eq("customer requested cancellation")
    end
  end

  describe "domain state predicates" do
    it "is billable and service-accessible only while active" do
      active_subscription = FactoryBot.build(:subscription)
      paused_subscription = FactoryBot.build(:subscription, :paused)
      cancelled_subscription = FactoryBot.build(:subscription, :cancelled)

      expect(active_subscription).to be_billable
      expect(active_subscription).to be_service_accessible
      expect(paused_subscription).not_to be_billable
      expect(paused_subscription).not_to be_service_accessible
      expect(cancelled_subscription).not_to be_billable
      expect(cancelled_subscription).not_to be_service_accessible
      expect(cancelled_subscription).to be_terminal
    end
  end
end
