class AddHumeSessionIdToMeetings < ActiveRecord::Migration[8.0]
  def change
    add_reference :meetings, :hume_session, foreign_key: true, type: :bigint
  end
end
