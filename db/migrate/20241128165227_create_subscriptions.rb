class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_enum :subscription_status, %i[active cancelled past_due partially_paid]

    create_table :subscriptions, id: :uuid do |t|
      t.enum :status, enum_type: :subscription_status, default: :active, null: false

      t.monetize :amount, currency: { present: false }, null: false

      t.datetime :current_period_start, null: false
      t.datetime :current_period_end,   null: false
      t.datetime :next_payment_attempt_at
      t.datetime :last_payment_at

      t.timestamps

      t.references :customer, null: false, foreign_key: true, type: :uuid

      t.index :current_period_end
      t.index %i[status next_payment_attempt_at]
    end
  end
end
