class CreateProcessedMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :processed_messages, id: :uuid do |t|
      t.string :consumer_name, null: false
      t.string :message_id, null: false

      t.timestamps
    end

    add_index :processed_messages, %i[consumer_name message_id], unique: true
  end
end
