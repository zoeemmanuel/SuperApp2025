# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_02_06_133744) do
  create_table "device_databases", force: :cascade do |t|
    t.integer "device_id", null: false
    t.string "path", null: false
    t.string "sync_token", null: false
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_sync_timestamp"
    t.string "sync_status"
    t.index ["device_id"], name: "index_device_databases_on_device_id"
    t.index ["last_sync_timestamp"], name: "index_device_databases_on_last_sync_timestamp"
    t.index ["path"], name: "index_device_databases_on_path", unique: true
    t.index ["sync_token"], name: "index_device_databases_on_sync_token", unique: true
  end

  create_table "device_databases_backup", force: :cascade do |t|
    t.integer "device_id"
    t.string "path"
    t.string "sync_token"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "devices", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "device_id"
    t.string "system_id"
    t.string "device_type"
    t.boolean "active"
    t.datetime "last_active_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "device_info"
    t.index ["device_id"], name: "index_devices_on_device_id", unique: true
    t.index ["system_id"], name: "index_devices_on_system_id", unique: true
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "devices_backup", force: :cascade do |t|
    t.integer "user_id"
    t.string "device_id"
    t.string "system_id"
    t.string "fingerprint"
    t.string "device_type"
    t.boolean "active"
    t.datetime "last_active_at"
    t.json "device_info"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "handle"
    t.string "phone"
    t.boolean "verified"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cloud_container_id"
    t.string "cloud_db_path"
    t.index ["cloud_db_path"], name: "index_users_on_cloud_db_path", unique: true
    t.index ["handle"], name: "index_users_on_handle", unique: true
    t.index ["phone"], name: "index_users_on_phone", unique: true
  end

  add_foreign_key "device_databases", "devices"
  add_foreign_key "devices", "users"
end
