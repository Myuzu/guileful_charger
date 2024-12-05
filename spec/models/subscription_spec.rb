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
end
