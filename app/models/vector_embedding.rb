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

  # Generate an embedding for the given text using OpenAI's embeddings API
  # @param text [String] The text to embed
  # @return [Array<Float>] The embedding vector
  def self.generate_embedding(text)
    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

    # Truncate text if necessary (OpenAI has a token limit)
    truncated_text = text.length > 8000 ? text[0..8000] : text

    response = client.embeddings(
      parameters: {
        model: "text-embedding-ada-002",
        input: truncated_text
      }
    )

    if response["data"] && response["data"][0] && response["data"][0]["embedding"]
      response["data"][0]["embedding"]
    else
      raise "Failed to generate embedding: #{response["error"]}"
    end
  end

  # Store content with its embedding
  # @param content [String] The content to store
  # @param content_type [String] The type of content
  # @param collection [String] The collection/namespace
  # @param task [Task] Optional associated task
  # @param project [Project] Optional associated project
  # @param metadata [Hash] Additional metadata
  # @return [VectorEmbedding] The created embedding
  def self.store(content:, content_type: "text", collection: "default",
                task: nil, project: nil, source_url: nil, source_title: nil, metadata: {})
    # Resolve project from task if not provided directly
    if project.nil? && task.present? && task.project.present?
      project = task.project
    end

    # Generate the embedding
    embedding = generate_embedding(content)

    # Create the record
    create!(
      content: content,
      content_type: content_type,
      collection: collection,
      task: task,
      project: project,
      source_url: source_url,
      source_title: source_title,
      metadata: metadata,
      embedding: embedding
    )
  end

  # Search for similar content
  # @param text [String] The query text
  # @param limit [Integer] Maximum number of results to return
  # @param collection [String] Optional collection to search within
  # @param task_id [Integer] Optional task_id to filter by
  # @param project_id [Integer] Optional project_id to filter by
  # @param distance [String] The distance metric to use ("euclidean", "cosine", "inner_product")
  # @return [Array<VectorEmbedding>] Matching embeddings sorted by similarity
  def self.search(text:, limit: 5, collection: nil, task_id: nil, project_id: nil, distance: "cosine")
    # Generate embedding for the query text
    query_embedding = generate_embedding(text)

    # Search for similar embeddings
    find_similar(
      query_embedding,
      limit: limit,
      collection: collection,
      task_id: task_id,
      project_id: project_id,
      distance: distance
    )
  end
end
