class AddFullTextSearch < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def up
    # 1. Add the tsvector column
    add_column :vector_embeddings, :content_tsv, :tsvector, if_not_exists: true

    # 2. Populate it for existing rows
    execute <<-SQL
      UPDATE vector_embeddings
      SET content_tsv = to_tsvector('english', COALESCE(content, ''))
    SQL

    # 3. Create a GIN index on the new column (CONCURRENTLY if large table)
    add_index :vector_embeddings, :content_tsv, using: :gin, algorithm: :concurrently, name: :index_vector_embeddings_on_content_tsv, if_not_exists: true
    add_index :vector_embeddings, [ :collection, :content ], name: :unique_collection_content, algorithm: :concurrently, if_not_exists: true


    # 4. Add trigger to keep tsvector up to date
    execute <<-SQL
      CREATE FUNCTION vector_embeddings_tsvector_update() RETURNS trigger AS $$
      begin
        new.content_tsv :=
          to_tsvector('english', coalesce(new.content, ''));
        return new;
      end
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_vector_embeddings_tsvector_update
      BEFORE INSERT OR UPDATE ON vector_embeddings
      FOR EACH ROW EXECUTE PROCEDURE vector_embeddings_tsvector_update();
    SQL
  end

  def down
    execute <<-SQL
      DROP TRIGGER IF EXISTS trg_vector_embeddings_tsvector_update ON vector_embeddings;
      DROP FUNCTION IF EXISTS vector_embeddings_tsvector_update();
    SQL
    remove_index :vector_embeddings, :content_tsv, if_exists: true
    remove_index :vector_embeddings, [ :collection, :content ], name: :unique_collection_content, if_exists: true
    remove_column :vector_embeddings, :content_tsv
  end
end
