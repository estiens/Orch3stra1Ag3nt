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
    # Start with a nearest neighbors query
    query = nearest_neighbors(:embedding, query_embedding, distance: distance)

    # Add collection filter if specified
    query = query.in_collection(collection) if collection.present?

    # Add task filter if specified
    query = query.for_task(task_id) if task_id.present?

    # Add project filter if specified
    query = query.for_project(project_id) if project_id.present?

    # Get nearest neighbors
    query.limit(limit)
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
    query = nearest_neighbors(:embedding, self.embedding, distance: distance)
    query.limit(limit)
  end
end
