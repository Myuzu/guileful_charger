class ProcessedMessage < ApplicationRecord
  validates :consumer_name, presence: true
  validates :message_id, presence: true, uniqueness: { scope: :consumer_name }
end
