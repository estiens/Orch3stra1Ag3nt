# frozen_string_literal: true

module Embedding
  # Handles database operations for vector embeddings
  class VectorStore
    attr_reader :collection, :task, :project, :logger
    
    # Constants for batch processing
    DB_COMMIT_FREQUENCY = 10
    
    def initialize(collection: nil, task: nil, project: nil)
      @task = task
      @project = project || task&.project
      @collection = collection || (@project ? "Project#{@project.id}" : "default")
      @logger = Embedding::Logger.new("VectorStore")
    end

    # Check if embedding exists
    def embedding_exists?(content, content_type: nil)
      conditions = { collection: @collection, content: content }
      conditions[:content_type] = content_type if content_type
      VectorEmbedding.exists?(conditions)
    end

    # More efficient filtering of existing chunks
    def filter_existing_chunks(chunks)
      return chunks if chunks.empty?

      # For large chunk sets, process in batches to avoid memory issues
      if chunks.size > 1000
        # Process in batches of 1000
        result = []
        chunks.each_slice(1000) do |batch|
          existing = VectorEmbedding.where(collection: @collection)
                                    .where(content: batch)
                                    .pluck(:content)
          result.concat(batch - existing)
        end
        result
      else
        # For smaller sets, process all at once
        existing_chunks = VectorEmbedding.where(collection: @collection)
                                         .where(content: chunks)
                                         .pluck(:content)
        chunks - existing_chunks
      end
    end

    # Remove all embeddings in collection
    def delete_all_embeddings_in_collection
      VectorEmbedding.where(collection: @collection).delete_all
    end

    # DANGEROUS: Truncate whole table!
    def truncate_embeddings
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE vector_embeddings RESTART IDENTITY;")
    end

    # Similarity search by vector
    def similarity_search_by_vector(embedding, k: 5, distance: "cosine")
      begin
        # Use the Neighbor gem's nearest_neighbors method directly with our scope
        VectorEmbedding.in_collection(@collection)
                      .nearest_neighbors(:embedding, embedding, distance: distance)
                      .limit(k)
      rescue => e
        @logger.error("Error in similarity_search_by_vector: #{e.message}")
        # Fallback to a simpler approach if the query fails
        ids = VectorEmbedding.in_collection(@collection).limit(k).pluck(:id)
        VectorEmbedding.where(id: ids)
      end
    end

    # Commit a batch of chunks and embeddings to the database
    def commit_batch_to_database(pending_chunks, pending_embeddings, original_text, chunk_size,
                                chunk_overlap, content_type, source_url, source_title, metadata, total_chunks)
      return [] if pending_chunks.empty? || pending_embeddings.empty?

      # Prepare base metadata
      base_metadata = prepare_base_metadata(
        original_text,
        chunk_size,
        chunk_overlap,
        content_type,
        source_url,
        source_title,
        metadata
      )

      # Build records for bulk insert
      records = []
      pending_chunks.zip(pending_embeddings).each_with_index do |(chunk, embedding), chunk_idx|
        next if embedding.nil?

        # Add chunk-specific metadata
        chunk_metadata = base_metadata.dup
        chunk_metadata[:chunk_index] = chunk_idx
        chunk_metadata[:chunk_count] = total_chunks

        records << {
          task_id: @task&.id,
          project_id: @project&.id,
          collection: @collection,
          content_type: content_type,
          content: chunk,
          source_url: source_url,
          source_title: source_title,
          metadata: chunk_metadata,
          embedding: embedding,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # Perform bulk insert
      if records.any?
        begin
          VectorEmbedding.insert_all!(records)
          # Get the actual records for return value
          VectorEmbedding.where(collection: @collection, content: pending_chunks)
        rescue => e
          Rails.logger.error("Database commit failed: #{e.message}")
          []
        end
      else
        []
      end
    end

    # Store a single embedding
    def store(content:, embedding:, content_type: "text", source_url: nil, source_title: nil, metadata: {})
      return if content.blank?

      # Prepare metadata
      full_metadata = prepare_metadata(content_type, source_url, source_title, metadata)

      # Create record
      VectorEmbedding.create!(
        task_id: @task&.id,
        project_id: @project&.id,
        collection: @collection,
        content_type: content_type,
        content: content,
        source_url: source_url,
        source_title: source_title,
        metadata: full_metadata,
        embedding: embedding
      )
    end

    private

    # Prepare base metadata for embeddings
    def prepare_base_metadata(original_text, chunk_size, chunk_overlap, content_type, source_url, source_title, metadata)
      full_metadata = {
        content_type: content_type,
        source_url: source_url,
        source_title: source_title,
        embedding_model: EmbeddingService::EMBEDDING_MODEL,
        timestamp: Time.now.iso8601,
        chunk_size: chunk_size,
        chunk_overlap: chunk_overlap,
        document_size: original_text.bytesize
      }

      # Add task and project info
      full_metadata[:task_id] = @task.id if @task
      full_metadata[:project_id] = @project.id if @project

      # Preserve file path information from metadata
      if metadata.present?
        %i[file_path file_name file_ext file_dir].each do |key|
          full_metadata[key] = metadata[key] if metadata[key].present?
        end

        # Merge remaining metadata
        full_metadata.merge!(metadata)
      end

      full_metadata
    end

    # Prepare metadata for embedding storage
    def prepare_metadata(content_type, source_url, source_title, metadata)
      full_metadata = {
        content_type: content_type,
        source_url: source_url,
        source_title: source_title,
        embedding_model: EmbeddingService::EMBEDDING_MODEL,
        timestamp: Time.now.iso8601
      }

      # Add task and project info
      full_metadata[:task_id] = @task.id if @task
      full_metadata[:project_id] = @project.id if @project

      # Merge additional metadata, preserving file path information
      if metadata.present?
        # Ensure file path information is preserved
        %i[file_path file_name file_ext file_dir].each do |key|
          full_metadata[key] = metadata[key] if metadata[key].present?
        end

        # Merge the rest
        full_metadata.merge!(metadata)
      end

      full_metadata
    end
  end
end
