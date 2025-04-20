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

ActiveRecord::Schema[8.0].define(version: 2025_04_20_182852) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "agent_activities", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.integer "parent_id"
    t.string "agent_type"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ancestry"
    t.jsonb "metadata", default: {}, null: false
    t.text "error_message"
    t.text "result"
    t.datetime "completed_at"
    t.index ["ancestry"], name: "index_agent_activities_on_ancestry"
    t.index ["task_id"], name: "index_agent_activities_on_task_id"
  end

  create_table "event_store_events", force: :cascade do |t|
    t.uuid "event_id", null: false
    t.string "event_type", null: false
    t.binary "metadata"
    t.binary "data", null: false
    t.datetime "created_at", null: false
    t.datetime "valid_at"
    t.index ["created_at"], name: "index_event_store_events_on_created_at"
    t.index ["event_id"], name: "index_event_store_events_on_event_id", unique: true
    t.index ["event_type"], name: "index_event_store_events_on_event_type"
    t.index ["valid_at"], name: "index_event_store_events_on_valid_at"
  end

  create_table "event_store_events_in_streams", force: :cascade do |t|
    t.string "stream", null: false
    t.integer "position"
    t.uuid "event_id", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_event_store_events_in_streams_on_created_at"
    t.index ["event_id"], name: "index_event_store_events_in_streams_on_event_id"
    t.index ["stream", "event_id"], name: "index_event_store_events_in_streams_on_stream_and_event_id", unique: true
    t.index ["stream", "position"], name: "index_event_store_events_in_streams_on_stream_and_position", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.bigint "agent_activity_id"
    t.string "event_type"
    t.text "data"
    t.datetime "occurred_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "processed_at"
    t.integer "processing_attempts", default: 0
    t.string "processing_error"
    t.integer "priority", default: 0
    t.bigint "task_id"
    t.bigint "project_id"
    t.index ["agent_activity_id"], name: "index_events_on_agent_activity_id"
    t.index ["event_type", "project_id"], name: "index_events_on_event_type_and_project_id"
    t.index ["event_type", "task_id"], name: "index_events_on_event_type_and_task_id"
    t.index ["event_type"], name: "index_events_on_event_type"
    t.index ["project_id"], name: "index_events_on_project_id"
    t.index ["task_id"], name: "index_events_on_task_id"
  end

  create_table "human_interactions", force: :cascade do |t|
    t.text "description"
    t.string "urgency", default: "normal"
    t.string "status", default: "pending", null: false
    t.text "resolution"
    t.bigint "agent_activity_id"
    t.datetime "acknowledged_at"
    t.datetime "resolved_at"
    t.datetime "dismissed_at"
    t.string "acknowledged_by"
    t.string "resolved_by"
    t.string "dismissed_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "interaction_type", null: false
    t.bigint "task_id"
    t.text "question"
    t.text "response"
    t.boolean "required", default: false, null: false
    t.datetime "expires_at"
    t.datetime "responded_at"
    t.string "answered_by"
    t.index ["agent_activity_id"], name: "index_human_interactions_on_agent_activity_id"
    t.index ["expires_at"], name: "index_human_interactions_on_expires_at"
    t.index ["interaction_type"], name: "index_human_interactions_on_interaction_type"
    t.index ["status", "urgency"], name: "index_human_interactions_on_status_and_urgency"
    t.index ["status"], name: "index_human_interactions_on_status"
    t.index ["task_id", "status"], name: "index_human_interactions_on_task_id_and_status"
    t.index ["task_id"], name: "index_human_interactions_on_task_id"
    t.index ["urgency"], name: "index_human_interactions_on_urgency"
  end

  create_table "llm_calls", force: :cascade do |t|
    t.bigint "agent_activity_id", null: false
    t.string "provider", default: "openrouter"
    t.string "model"
    t.text "prompt"
    t.text "response"
    t.integer "tokens_used", default: 0
    t.text "request_payload"
    t.text "response_payload"
    t.float "duration"
    t.decimal "cost"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "prompt_tokens", default: 0
    t.integer "completion_tokens", default: 0
    t.integer "prompt_id"
    t.index ["agent_activity_id"], name: "index_llm_calls_on_agent_activity_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "pending"
    t.integer "priority", default: 5
    t.jsonb "settings", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "due_date"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_projects_on_name"
    t.index ["priority"], name: "index_projects_on_priority"
    t.index ["status"], name: "index_projects_on_status"
  end

  create_table "prompt_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_prompt_categories_on_slug", unique: true
  end

  create_table "prompts", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.boolean "active", default: true
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_prompts_on_slug", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "tasks", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "state"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "parent_id"
    t.string "task_type", default: "general"
    t.json "metadata"
    t.string "priority", default: "normal"
    t.text "result"
    t.bigint "project_id"
    t.index ["parent_id"], name: "index_tasks_on_parent_id"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["state"], name: "index_tasks_on_state"
    t.index ["task_type"], name: "index_tasks_on_task_type"
  end

  create_table "vector_embeddings", force: :cascade do |t|
    t.bigint "task_id"
    t.string "collection", default: "default", null: false
    t.string "content_type", default: "text", null: false
    t.text "content", null: false
    t.string "source_url"
    t.string "source_title"
    t.jsonb "metadata", default: {}, null: false
    t.vector "embedding", limit: 1024, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "project_id"
    t.tsvector "content_tsv"
    t.index ["collection", "content"], name: "unique_collection_content", unique: true
    t.index ["collection"], name: "index_vector_embeddings_on_collection"
    t.index ["content_tsv"], name: "index_vector_embeddings_on_content_tsv", using: :gin
    t.index ["content_type"], name: "index_vector_embeddings_on_content_type"
    t.index ["embedding"], name: "index_vector_embeddings_on_embedding", opclass: :vector_l2_ops, using: :hnsw
    t.index ["project_id"], name: "index_vector_embeddings_on_project_id"
    t.index ["task_id"], name: "index_vector_embeddings_on_task_id"
  end

  add_foreign_key "agent_activities", "tasks"
  add_foreign_key "event_store_events_in_streams", "event_store_events", column: "event_id", primary_key: "event_id"
  add_foreign_key "events", "agent_activities"
  add_foreign_key "events", "projects"
  add_foreign_key "events", "tasks"
  add_foreign_key "human_interactions", "agent_activities"
  add_foreign_key "human_interactions", "tasks"
  add_foreign_key "llm_calls", "agent_activities"
  add_foreign_key "llm_calls", "prompts"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "tasks", "projects"
  add_foreign_key "vector_embeddings", "projects"
  add_foreign_key "vector_embeddings", "tasks"
end
