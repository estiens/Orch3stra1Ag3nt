class VectorEmbedding < ApplicationRecord
  belongs_to :task, optional: true
  belongs_to :project, optional: true

  # Set up nearest neighbor search on the embedding vector
  has_neighbors :embedding

  # Validations
  validates :content, presence: true
  validates :content_type, presence: true
  validates :collection, presence: true

  # Scopes
  scope :in_collection, ->(collection) { where(collection: collection) }
  scope :by_content_type, ->(type) { where(content_type: type) }
  scope :for_task, ->(task_id) { where(task_id: task_id) }
  scope :for_project, ->(project_id) { where(project_id: project_id) }

  scope :search_content, ->(query) { where("content @@ websearch_to_tsquery(?)", query) }

  # Find similar embeddings with a vector similarity search using Neighbor
  # @param query_embedding [Array] The query embedding vector
  # @param limit [Integer] Maximum number of results to return
  # @param collection [String] Optional collection to search within
  # @param task_id [Integer] Optional task_id to filter by
  # @param project_id [Integer] Optional project_id to filter by
  # @param distance [String] The distance metric to use ("euclidean", "cosine", "inner_product")
  # @return [Array<VectorEmbedding>] Matching embeddings sorted by similarity
  def self.find_similar(query_embedding, limit: 5, collection: nil, task_id: nil, project_id: nil, distance: "cosine")
    # First get IDs that match our filters
    query = self
    query = query.in_collection(collection) if collection.present?
    query = query.for_task(task_id) if task_id.present?
    query = query.for_project(project_id) if project_id.present?
    
    # Get the IDs that match our filters
    filtered_ids = query.pluck(:id)
    return [] if filtered_ids.empty?
    
    # Use a simpler approach that avoids the SQL syntax error
    # This uses the raw SQL approach from the Neighbor gem
    begin
      # Use the basic where clause approach which is more reliable
      results = VectorEmbedding.where(id: filtered_ids)
      
      # Apply the nearest neighbors search
      case distance
      when "cosine"
        results = results.order(Arel.sql("embedding <=> ARRAY[#{query_embedding.join(',')}]::vector"))
      when "inner_product"
        results = results.order(Arel.sql("embedding <#> ARRAY[#{query_embedding.join(',')}]::vector"))
      else # euclidean
        results = results.order(Arel.sql("embedding <-> ARRAY[#{query_embedding.join(',')}]::vector"))
      end
      
      results.limit(limit)
    rescue => e
      Rails.logger.error("Error in find_similar: #{e.message}")
      # Fallback to a simpler approach if the query fails
      VectorEmbedding.where(id: filtered_ids).limit(limit)
    end
  end

  # Generate an embedding for the given text using the embedding service
  # @param text [String] The text to embed
  # @return [Array<Float>] The embedding vector
  def self.generate_embedding(text)
    EmbeddingService.new.generate_embedding(text)
  end

  def similarity(other_embedding)
    # Calculate the cosine similarity between two vectors
    dot_product = self.embedding.zip(other_embedding).map { |a, b| a * b }.sum
    magnitude_self = Math.sqrt(self.embedding.map { |a| a * a }.sum)
    magnitude_other = Math.sqrt(other_embedding.map { |a| a * a }.sum)
    dot_product / (magnitude_self * magnitude_other)
  end

  def similar_to_me(limit: 5, distance: "cosine")
    # Get IDs in the same collection, excluding self
    collection_ids = VectorEmbedding.where(collection: self.collection)
                                   .where.not(id: self.id)
                                   .pluck(:id)
    return [] if collection_ids.empty?
    
    # Use a simpler approach that avoids the SQL syntax error
    begin
      # Use the basic where clause approach which is more reliable
      results = VectorEmbedding.where(id: collection_ids)
      
      # Apply the nearest neighbors search using raw SQL operators
      case distance
      when "cosine"
        results = results.order(Arel.sql("embedding <=> ARRAY[#{self.embedding.join(',')}]::vector"))
      when "inner_product"
        results = results.order(Arel.sql("embedding <#> ARRAY[#{self.embedding.join(',')}]::vector"))
      else # euclidean
        results = results.order(Arel.sql("embedding <-> ARRAY[#{self.embedding.join(',')}]::vector"))
      end
      
      results.limit(limit)
    rescue => e
      Rails.logger.error("Error in similar_to_me: #{e.message}")
      # Fallback to a simpler approach if the query fails
      VectorEmbedding.where(id: collection_ids).limit(limit)
    end
  end
end
