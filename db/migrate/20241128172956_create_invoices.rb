class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_enum :invoice_status, Invoice::VALID_STATUSES

    create_table :invoices, id: :uuid do |t|
      t.enum :status, enum_type: :invoice_status, default: :draft, null: false

      t.monetize :amount, currency: { present: false }, null: false

      t.datetime :due_date
      t.datetime :issued_at
      t.datetime :paid_at

      t.references :customer,     null: false, foreign_key: true, type: :uuid
      t.references :subscription, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
