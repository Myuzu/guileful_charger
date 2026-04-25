class CreateOutboxMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :outbox_messages, id: :uuid do |t|
      t.string :topic, null: false
      t.jsonb :payload, default: {}, null: false
      t.string :aggregate_type
      t.uuid :aggregate_id
      t.integer :aggregate_version
      t.datetime :published_at
      t.integer :attempts, default: 0, null: false
      t.text :last_error

      t.timestamps
    end

    add_index :outbox_messages, :published_at
    add_index :outbox_messages, %i[aggregate_type aggregate_id]
    add_index :outbox_messages, %i[published_at created_at]
  end
end
