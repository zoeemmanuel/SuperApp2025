require 'sqlite3'

Rails.application.config.after_initialize do
  # Ensure devices directory exists
  FileUtils.mkdir_p(Rails.root.join('db', 'devices'))
  
  # Set SQLite3 busy timeout to avoid database locks
  SQLite3::Database.new(':memory:').busy_timeout = 5000
end
