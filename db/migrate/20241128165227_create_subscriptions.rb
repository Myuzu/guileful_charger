class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_enum :subscription_status, %i[active cancelled paused]

    create_table :subscriptions, id: :uuid do |t|
      t.enum :status, enum_type: :subscription_status, default: :active, null: false

      t.monetize :amount, currency: { present: false }, null: false

      t.datetime :current_period_start, null: false
      t.datetime :current_period_end,   null: false

      # AASM status timestamps
      t.datetime :active_at
      t.datetime :cancelled_at
      t.datetime :paused_at

      t.text :cancellation_reason

      t.references :customer, null: false, foreign_key: true, type: :uuid

      t.timestamps

      t.index %i[status current_period_end]
    end
  end
end
