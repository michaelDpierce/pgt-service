class CreateMeetings < ActiveRecord::Migration[8.0]
  def change
    create_table :meetings, id: :uuid do |t|
      t.string   :title, null: false
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.timestamps
    end
  end
end
