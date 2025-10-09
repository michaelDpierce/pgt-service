class HumeSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :hume_sessions do |t|
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
  end
end