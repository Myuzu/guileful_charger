class AddLockedAtToOutboxMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :outbox_messages, :locked_at, :datetime
    add_index :outbox_messages, :locked_at
  end
end
