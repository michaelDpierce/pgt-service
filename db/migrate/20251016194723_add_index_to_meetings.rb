class AddIndexToMeetings < ActiveRecord::Migration[8.0]
  def change
    add_index :meetings, :title
  end
end
