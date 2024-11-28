class CreateCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :customers, id: :uuid do |t|
      t.string :name
      t.text :email
      t.text :billing_address

      t.timestamps
    end
    add_index :customers, :email, unique: true
  end
end
