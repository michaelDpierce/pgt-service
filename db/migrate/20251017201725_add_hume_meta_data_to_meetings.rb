class AddHumeMetaDataToMeetings < ActiveRecord::Migration[8.0]
  def change
    add_column :meetings, :hume_label,  :string, null: true
    add_column :meetings, :hume_config, :string, null: true
  end
end
