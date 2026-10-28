# typed: false

require "rails_helper"
require Rails.root.join("db/migrate/20261028140000_update_postgresql_extensions")

RSpec.describe UpdatePostgresqlExtensions do
  describe "#up" do
    let(:connection) { ActiveRecord::Base.connection }
    let(:infinite_time_partitions) do
      connection.select_value(<<~SQL)
        SELECT infinite_time_partitions
        FROM partman.part_config
        WHERE parent_table = 'public.outbox_messages_published';
      SQL
    end

    before do
      connection.execute(<<~SQL)
        UPDATE partman.part_config
        SET infinite_time_partitions = false
        WHERE parent_table = 'public.outbox_messages_published';
      SQL
    end

    it "enables partition creation during idle periods" do
      described_class.new.up

      expect(infinite_time_partitions).to be(true)
    end

    context "when the published outbox is empty" do
      let(:future_partition) do
        connection.select_value(<<~SQL)
          SELECT partition_tablename
          FROM partman.show_partitions('public.outbox_messages_published', 'DESC')
          LIMIT 1;
        SQL
      end

      before do
        connection.execute("DELETE FROM outbox_messages_published")
        connection.execute(<<~SQL)
          SELECT partman.create_partition_time(
            'public.outbox_messages_published', ARRAY[(CURRENT_DATE + 7)::timestamptz]
          );
        SQL
        connection.execute("DROP TABLE #{connection.quote_table_name(future_partition)}")
      end

      it "recreates a missing future partition during maintenance" do
        described_class.new.up
        connection.execute("SELECT partman.run_maintenance('public.outbox_messages_published')")

        expect(connection.table_exists?(future_partition)).to be(true)
      end
    end
  end

  describe "#down" do
    it "rejects extension downgrades" do
      expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
