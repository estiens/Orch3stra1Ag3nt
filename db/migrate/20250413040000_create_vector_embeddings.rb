class CreateVectorEmbeddings < ActiveRecord::Migration[8.0]
  def up
    # Enable pgvector extension
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # Create embeddings table
    create_table :vector_embeddings do |t|
      t.references :task, null: true, foreign_key: true, index: true
      t.string :collection, null: false, default: 'default'  # Collection/namespace for organizing embeddings
      t.string :content_type, null: false, default: 'text'   # text, url, code, etc.
      t.text :content, null: false                           # The actual content that was embedded
      t.string :source_url                                   # URL source if available
      t.string :source_title                                 # Title of the source
      t.jsonb :metadata, null: false, default: {}            # Additional metadata
      t.vector :embedding, limit: 1536, null: false          # OpenAI ada-002 model dimensionality
      t.timestamps
    end

    # Add indices for common queries
    add_index :vector_embeddings, :collection
    add_index :vector_embeddings, :content_type

    # Add an index for vector similarity search using HNSW
    add_index :vector_embeddings, :embedding, using: :hnsw, opclass: :vector_l2_ops

    # If you prefer IVFFlat, use this instead (faster to build, slower to query than HNSW)
    # add_index :vector_embeddings, :embedding, using: :ivfflat, opclass: :vector_l2_ops, with: { lists: 100 }
  end

  def down
    drop_table :vector_embeddings
    execute "DROP EXTENSION IF EXISTS vector"
  end
end
