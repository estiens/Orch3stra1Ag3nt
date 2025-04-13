class VectorEmbeddingTool < BaseTool
  def initialize
    super("vector_embedding", "Store and retrieve vector embeddings")
  end
  
  def call(args)
    action = args[:action]
    content = args[:content]
    collection = args[:collection] || "default"
    task_id = args[:task_id]
    project_id = args[:project_id]
    limit = args[:limit] || 5
    content_type = args[:content_type] || "text"
    metadata = args[:metadata] || {}
    source_url = args[:source_url]
    source_title = args[:source_title]
    begin
      # Validate OpenAI API key
      unless ENV["OPENAI_API_KEY"].present?
        return { error: "OPENAI_API_KEY environment variable is not set" }
      end

      # Get task and/or project if IDs provided
      task = task_id.present? ? Task.find_by(id: task_id) : nil
      project = project_id.present? ? Project.find_by(id: project_id) : nil

      # If task is provided but not project, try to get project from task
      if project.nil? && task&.project.present?
        project = task.project
      end

      case action.to_s.downcase
      when "store"
        # Validate content
        unless content.present?
          return { error: "Content is required for 'store' action" }
        end

        # Store the embedding
        embedding = VectorEmbedding.store(
          content: content,
          content_type: content_type,
          collection: collection,
          task: task,
          project: project,
          source_url: source_url,
          source_title: source_title,
          metadata: metadata || {}
        )

        {
          success: true,
          action: "store",
          embedding_id: embedding.id,
          collection: embedding.collection,
          message: "Content stored successfully with embedding"
        }

      when "search"
        # Validate search query
        unless content.present?
          return { error: "Content is required for 'search' action" }
        end

        # Search for similar content
        results = VectorEmbedding.search(
          text: content,
          limit: limit.to_i,
          collection: collection,
          task_id: task_id,
          project_id: project_id
        )

        # Format the results
        formatted_results = results.map do |result|
          {
            id: result.id,
            content: result.content.truncate(300),
            content_type: result.content_type,
            collection: result.collection,
            source_url: result.source_url,
            source_title: result.source_title,
            created_at: result.created_at,
            task_id: result.task_id,
            project_id: result.project_id,
            metadata: result.metadata
          }
        end

        {
          success: true,
          action: "search",
          query: content,
          collection: collection,
          results_count: results.size,
          results: formatted_results
        }

      when "list_collections"
        # Add filters for task or project if provided
        query = VectorEmbedding
        query = query.where(task_id: task_id) if task_id.present?
        query = query.where(project_id: project_id) if project_id.present?

        # Get unique collections with counts
        collections = query.group(:collection)
                         .select("collection, COUNT(*) as count")
                         .order("count DESC")

        # Format the results
        formatted_collections = collections.map do |c|
          { name: c.collection, count: c.count }
        end

        {
          success: true,
          action: "list_collections",
          filter_by_task_id: task_id,
          filter_by_project_id: project_id,
          collections: formatted_collections
        }

      else
        { error: "Unknown action: #{action}. Valid actions are 'store', 'search', and 'list_collections'" }
      end

    rescue ActiveRecord::RecordNotFound
      { error: "Resource not found: task_id=#{task_id}, project_id=#{project_id}" }
    rescue => e
      { error: "Error in semantic memory tool: #{e.message}" }
    end
  end
end
