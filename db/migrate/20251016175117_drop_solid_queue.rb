class DropSolidQueue < ActiveRecord::Migration[8.0]
  def up
    # Find all tables that start with 'solid_queue_'
    solid_queue_tables = ActiveRecord::Base.connection.tables.grep(/^solid_queue_/)

    # Drop in a stable order (FKs usually point from executions -> jobs -> queues/processes)
    preferred_order = %w[
      solid_queue_blocked_executions
      solid_queue_failed_executions
      solid_queue_recurring_executions
      solid_queue_scheduled_executions
      solid_queue_claimed_jobs
      solid_queue_jobs
      solid_queue_queues
      solid_queue_processes
      solid_queue_locks
      solid_queue_semaphores
    ]

    (preferred_order & solid_queue_tables).each do |t|
      say "Dropping #{t}"
      drop_table t, if_exists: true
    end

    # Drop any stragglers we didn't list explicitly
    (solid_queue_tables - preferred_order).each do |t|
      say "Dropping #{t}"
      drop_table t, if_exists: true
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Re-run solid_queue:install to restore tables."
  end
end
