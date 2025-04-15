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
    begin
      # Log the embedding format to help with debugging
      Rails.logger.debug("Query embedding format: #{query_embedding.class}, dimensions: #{query_embedding.size}")

      # Use nearest_neighbors from the Neighbor gem which safely handles vector queries
      query = nearest_neighbors(:embedding, query_embedding, distance: distance)
      query = query.in_collection(collection) if collection.present?
      query = query.for_task(task_id) if task_id.present?
      query = query.for_project(project_id) if project_id.present?
      query.limit(limit)
    rescue => e
      Rails.logger.error("Error in find_similar: #{e.message}")
      Rails.logger.error("Embedding format that caused error: #{query_embedding.class}, #{query_embedding.inspect[0..100]}")

      # Fallback to a simpler approach if the query fails
      query = self
      query = query.in_collection(collection) if collection.present?
      query = query.for_task(task_id) if task_id.present?
      query = query.for_project(project_id) if project_id.present?

      filtered_ids = query.pluck(:id)
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
    begin
      # Ensure both are arrays
      vec1 = embedding.is_a?(Array) ? embedding : embedding.to_a
      vec2 = other_embedding.is_a?(Array) ? other_embedding : other_embedding.to_a

      # Check dimensions
      unless vec1.size == vec2.size
        Rails.logger.warn("Vector dimension mismatch: #{vec1.size} vs #{vec2.size}")
        return 0.0
      end

      # Calculate cosine similarity
      dot_product = vec1.zip(vec2).sum { |a, b| a * b }
      magnitude1 = Math.sqrt(vec1.sum { |a| a * a })
      magnitude2 = Math.sqrt(vec2.sum { |a| a * a })

      # Handle zero magnitudes to avoid division by zero
      product = magnitude1 * magnitude2
      return 0.0 if product.zero?

      dot_product / product
    rescue => e
      Rails.logger.error("Error calculating similarity: #{e.message}")
      0.0
    end
  end

  def similar_to_me(limit: 5, distance: "cosine")
    begin
      # Use nearest_neighbors from the Neighbor gem which safely handles vector queries
      VectorEmbedding
        .nearest_neighbors(:embedding, self.embedding, distance: distance)
        .in_collection(self.collection)
        .where.not(id: self.id)
        .limit(limit)
    rescue => e
      Rails.logger.error("Error in similar_to_me: #{e.message}")
      # Fallback to a simpler approach if the query fails
      collection_ids = VectorEmbedding.in_collection(self.collection)
                                     .where.not(id: self.id)
                                     .pluck(:id)
      VectorEmbedding.where(id: collection_ids).limit(limit)
    end
  end
end
