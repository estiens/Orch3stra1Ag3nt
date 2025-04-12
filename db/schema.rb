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

ActiveRecord::Schema[8.0].define(version: 2025_04_12_215421) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_activities", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.integer "parent_id"
    t.string "agent_type"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ancestry"
    t.index ["ancestry"], name: "index_agent_activities_on_ancestry"
    t.index ["task_id"], name: "index_agent_activities_on_task_id"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "agent_activity_id", null: false
    t.string "event_type"
    t.text "data"
    t.datetime "occurred_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_activity_id"], name: "index_events_on_agent_activity_id"
  end

  create_table "llm_calls", force: :cascade do |t|
    t.bigint "agent_activity_id", null: false
    t.text "request_payload"
    t.text "response_payload"
    t.float "duration"
    t.decimal "cost"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_activity_id"], name: "index_llm_calls_on_agent_activity_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "state"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "agent_activities", "tasks"
  add_foreign_key "events", "agent_activities"
  add_foreign_key "llm_calls", "agent_activities"
end
