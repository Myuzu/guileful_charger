class CreateCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :customers, id: :uuid do |t|
      t.string :name,          null: false
      t.text :email,           null: false
      t.text :billing_address, null: false

      t.timestamps
    end
    add_index :customers, :email, unique: true
  end
end
