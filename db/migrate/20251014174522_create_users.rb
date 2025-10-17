class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :uuid do |t|
      t.string :clerk_id, null: false
      t.string :email
      t.string :full_name
      t.string :first_name
      t.string :last_name
      t.string :avatar_url
      t.timestamps
    end

    add_index :users, :clerk_id, unique: true
  end
end
