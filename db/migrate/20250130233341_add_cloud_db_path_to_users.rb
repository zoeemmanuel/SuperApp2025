class AddCloudDbPathToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :cloud_db_path, :string
    add_index :users, :cloud_db_path, unique: true
  end
end
