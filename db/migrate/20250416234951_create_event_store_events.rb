# frozen_string_literal: true

class CreateEventStoreEvents < ActiveRecord::Migration[8.0]
  def change
    create_table(:event_store_events, id: :bigserial, force: false) do |t|
      t.references  :event,       null: false, type: :uuid, index: { unique: true }
      t.string      :event_type,  null: false, index: true
      t.binary      :metadata
      t.binary      :data, null: false
      t.datetime    :created_at,  null: false, type: :timestamp, precision: 6, index: true
      t.datetime    :valid_at,    null: true, type: :timestamp, precision: 6, index: true
    end

    create_table(:event_store_events_in_streams, id: :bigserial, force: false) do |t|
      t.string      :stream,      null: false
      t.integer     :position,    null: true
      t.references  :event,       null: false, type: :uuid, index: true, foreign_key: { to_table: :event_store_events, primary_key: :event_id }
      t.datetime    :created_at,  null: false, type: :timestamp, precision: 6, index: true

      t.index [ :stream, :position ], unique: true
      t.index [ :stream, :event_id ], unique: true
    end
  end
end
