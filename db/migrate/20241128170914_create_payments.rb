class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_enum :payment_status, Payment::VALID_STATUSES

    create_table :payments, id: :uuid do |t|
      t.enum :status, enum_type: :payment_status, default: :pending, null: false

      t.monetize :amount, currency: { present: false }, null: false

      t.string :transaction_id, null: false
      t.datetime :paid_at
      t.text :failure_reason

      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.references :invoice,  null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
