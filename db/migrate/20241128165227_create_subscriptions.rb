class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_enum :subscription_status, Subscription::VALID_STATUSES

    create_table :subscriptions, id: :uuid do |t|
      t.enum :status, enum_type: :subscription_status, default: :active, null: false

      t.monetize :amount, currency: { present: false }, null: false

      t.integer :billing_cycle_count
      t.datetime :next_billing_at, null: false
      t.references :customer, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
