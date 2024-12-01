class CreatePaymentAttempts < ActiveRecord::Migration[8.0]
  def change
    create_enum :payment_attempt_status, %i[pending in_progress completed failed]

    create_table :payment_attempts, id: :uuid do |t|
      t.enum :status, enum_type: :payment_attempt_status, default: :pending, null: false

      t.monetize :amount, currency: { present: false }, null: false

      t.integer :attempt_number, null: false

      t.text :transaction_id
      t.text :failure_reason

      t.datetime :paid_at
      t.datetime :scheduled_at, null: false
      t.datetime :processed_at

      t.timestamps

      t.references :customer,     null: false, foreign_key: true, type: :uuid
      t.references :subscription, null: false, foreign_key: true, type: :uuid

      t.index %i[subscription_id status]
      t.index :scheduled_at
    end
  end
end
