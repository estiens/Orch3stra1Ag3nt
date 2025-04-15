# frozen_string_literal: true

class EmbeddingTool
  extend Langchain::ToolDefinition

  # Constants for default values
  DEFAULT_COLLECTION = "default"
  DEFAULT_CONTENT_TYPE = "text"
  DEFAULT_LIMIT = 5
  DEFAULT_DISTANCE = "euclidean"
  DEFAULT_CHUNK_SIZE = 500
  DEFAULT_CHUNK_OVERLAP = 25
  MAX_CHUNK_SIZE = 5000
  MAX_CONTENT_PREVIEW = 200

  # Unified data addition: accepts a String or Array, and can do chunking if requested
  define_function :add, description: "Add one or more texts/documents to the vector database; can also chunk a large document" do
    property :texts, type: "array", description: "Array of texts to embed. For a single text, just provide one item.", required: true
    property :content_type, type: "string", description: "The type of content", required: false
    property :collection, type: "string", description: "The collection to add to", required: false
    property :chunk_size, type: "integer", description: "Chunk large texts into segments of this size (optional)", required: false
    property :chunk_overlap, type: "integer", description: "Chunk overlap when chunking (optional)", required: false
    property :source_url, type: "string", description: "Source URL of the content", required: false
    property :source_title, type: "string", description: "Title of the source", required: false
    property :metadata, type: "object", description: "Additional metadata", required: false
  end

  # Unified similarity search (optionally allows hyde or other modes)
  define_function :similarity_search, description: "Search for similar content (semantic vector search) in the vector database" do
    property :query, type: "string", description: "The query text", required: true
    property :limit, type: "integer", description: "Maximum number of results", required: false
    property :collection, type: "string", description: "The collection to search", required: false
    property :distance, type: "string", description: "Distance metric (cosine, euclidean, inner_product)", required: false
    property :mode, type: "string", description: "Optional search mode (e.g., 'hyde' for HyDE retrieval)", required: false
  end

  # RAG QA (optional: just wraps a similarity search and LLM answer)
  define_function :ask, description: "Answer a question using RAG (Retrieval Augmented Generation)" do
    property :question, type: "string", description: "The question to answer", required: true
    property :limit, type: "integer", description: "Number of documents to retrieve", required: false
    property :collection, type: "string", description: "The collection to search", required: false
  end

  # LLM provider - lazy-initialized
  def llm
    @llm ||= Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: Rails.configuration.llm[:models][:fast],
        temperature: 0.2
      }
    )
  end

    def fetch_directory_files(directory, pattern)
      files = []

      # Use Dir.glob to get all files recursively
      Dir.glob(File.join(directory, "**", "*")).each do |file|
        # Check if it's a file
        if File.file?(file)
          # If there's a pattern, match it; otherwise, add all files
          if pattern.nil? || File.fnmatch(pattern, File.basename(file))
            files << file
          end
        end
      end

      files
    end

  def add_directory(directory, pattern: nil, content_type: nil, collection: DEFAULT_COLLECTION)
    # Validate directory
    raise ArgumentError, "Directory not found: #{directory}" unless File.directory?(directory)
    raise ArgumentError, "Directory is not readable: #{directory}" unless File.readable?(directory)
    files = fetch_directory_files(directory, pattern)
    raise ArgumentError, "No files found in directory: #{directory}" if files.empty?
    add_files(files: files, content_type: content_type, collection: collection)
  end

  # Add files to the vector database
  def add_files(
    files:,
    content_type: nil, # Allow auto-detection from file extension
    collection: DEFAULT_COLLECTION,
    chunk_size: DEFAULT_CHUNK_SIZE,
    chunk_overlap: DEFAULT_CHUNK_OVERLAP,
    source_url: nil,
    source_title: nil,
    metadata: {},
    batch_size: 5 # Process this many files in parallel
  )
    # Validate parameters
    validate_chunking_params(chunk_size, chunk_overlap)

    # Initialize service and normalize input
    service = EmbeddingService.new(collection: collection)
    files_array = to_array(files)
    raise ArgumentError, "You must supply at least one file." if files_array.empty?

    start_time = Time.now
    total_files = files_array.size
    Rails.logger.tagged("EmbeddingTool", "add_files") do
      Rails.logger.info("Starting batch processing of #{total_files} files with batch size #{batch_size}")
    
      # Process files in batches
      added = []
      total_processed = 0
      total_successful = 0
      
      files_array.each_slice(batch_size).with_index do |batch, batch_idx|
        batch_start = Time.now
        batch_num = batch_idx + 1
        batch_size = batch.size
        total_batches = (total_files.to_f / batch_size).ceil
        
        Rails.logger.info("Processing batch #{batch_num}/#{total_batches} with #{batch_size} files")
        
        # Prepare file data for parallel processing
        file_data = batch.map do |file|
          begin
            file_obj = validate_and_open_file(file)
            file_path = file_obj.respond_to?(:path) ? file_obj.path : "unknown"

            # Determine content type if not provided
            detected_content_type = content_type
            if detected_content_type.nil? && file_obj.respond_to?(:path)
              ext = File.extname(file_obj.path).downcase
              detected_content_type = case ext
              when ".md", ".txt", ".text" then "text"
              when ".html", ".htm" then "html"
              when ".pdf" then "pdf"
              when ".doc", ".docx" then "document"
              when ".rb", ".py", ".js", ".java", ".c", ".cpp" then "code"
              when ".json", ".xml", ".yaml", ".yml" then "data"
              else DEFAULT_CONTENT_TYPE
              end
            end

            # Prepare file-specific metadata
            file_metadata = build_file_metadata(
              file_obj,
              merge: metadata,
              content_type: detected_content_type,
              source_url: source_url,
              source_title: source_title
            )

            # Read file content
            begin
              file_content = file_obj.read
              
              # Return a hash with all the data needed for processing
              {
                content: file_content,
                path: file_path,
                size: file_obj.size,
                content_type: detected_content_type,
                metadata: file_metadata,
                source_url: source_url || file_path,
                source_title: source_title || File.basename(file_path)
              }
            rescue => e
              Rails.logger.error("Error reading file #{file_path}: #{e.message}")
              {
                path: file_path,
                error: "Failed to read file: #{e.message}",
                status: "error"
              }
            end
          rescue => e
            Rails.logger.error("Error preparing file: #{e.message}")
            {
              path: file.respond_to?(:path) ? file.path : file.to_s,
              error: "Processing error: #{e.message}",
              status: "error"
            }
          end
        end
        
        # Filter out files with errors
        valid_files = file_data.select { |f| !f[:error] }
        error_files = file_data.select { |f| f[:error] }
        
        # Process valid files in parallel using threads
        batch_results = []
        batch_results.concat(error_files) # Add error files to results
        
        if valid_files.any?
          # Log the files we're about to process
          valid_files.each do |file|
            Rails.logger.info("Processing file: #{file[:path]} (#{file[:size]} bytes, type: #{file[:content_type]})")
          end
          
          # Use threads for parallel processing
          threads = valid_files.map do |file|
            Thread.new do
              begin
                # Process the file with the embedding service
                result = service.add_document(
                  file[:content],
                  chunk_size: chunk_size,
                  chunk_overlap: chunk_overlap,
                  content_type: file[:content_type],
                  source_url: file[:source_url],
                  source_title: file[:source_title],
                  metadata: file[:metadata]
                )
                
                # Return the result
                {
                  path: file[:path],
                  size: file[:size],
                  content_type: file[:content_type],
                  chunk_preview: result.first&.content&.first(40),
                  chunks: result.count,
                  status: "success"
                }
              rescue => e
                Rails.logger.error("Error processing file #{file[:path]}: #{e.message}")
                {
                  path: file[:path],
                  error: "Processing error: #{e.message}",
                  status: "error"
                }
              end
            end
          end
          
          # Wait for all threads to complete and collect results
          thread_results = threads.map(&:value)
          batch_results.concat(thread_results)
        end
        
        # Add batch results to overall results
        added.concat(batch_results)
        total_processed += batch_size
        batch_successful = batch_results.count { |item| item[:status] == "success" }
        total_successful += batch_successful
        
        # Log batch completion
        batch_time = Time.now - batch_start
        Rails.logger.info("Batch #{batch_num}/#{total_batches} completed in #{batch_time.round(2)}s " +
                         "(#{batch_successful}/#{batch_size} successful, " +
                         "#{total_processed}/#{total_files} total processed)")
      end
      
      # Log final stats
      total_time = Time.now - start_time
      Rails.logger.info("File processing complete: #{total_successful}/#{total_files} files processed successfully " +
                       "in #{total_time.round(2)}s (#{(total_time/60).round(1)} minutes)")
      
      {
        status: "success",
        message: "Files processed successfully",
        added: added,
        total_count: added.count,
        successful_count: added.count { |item| item[:status] == "success" },
        processing_time: total_time.round(2)
      }
    end
  end

  # Add text(s) to the vector database
  def add(
    texts:,
    content_type: DEFAULT_CONTENT_TYPE,
    collection: DEFAULT_COLLECTION,
    chunk_size: nil,
    chunk_overlap: nil,
    source_url: nil,
    source_title: nil,
    metadata: {}
  )
    # Validate chunking parameters if provided
    validate_chunking_params(chunk_size, chunk_overlap) if chunk_size

    # Initialize service and normalize input
    service = EmbeddingService.new(collection: collection)
    items = to_array(texts)
    raise ArgumentError, "You must supply at least one text." if items.empty?

    # Process each text
    added = []
    items.each do |text|
      # Prepare metadata
      text_metadata = build_metadata(
        content_type: content_type,
        source_url: source_url,
        source_title: source_title,
        extra: metadata
      )

      # If chunking is requested, delegate to the chunk-aware method
      if chunk_size
        embeddings = service.add_document(
          text,
          chunk_size: chunk_size,
          chunk_overlap: chunk_overlap || 0,
          content_type: content_type,
          source_url: source_url,
          source_title: source_title,
          metadata: text_metadata
        )
        added << {
          status: "success",
          message: "Document added with #{embeddings.count} chunks",
          chunk_count: embeddings.count
        }
      else
        embedding = service.add_text(
          text,
          content_type: content_type,
          source_url: source_url,
          source_title: source_title,
          metadata: text_metadata
        )
        added << {
          status: "success",
          message: "Text added",
          embedding_id: embedding&.id || "unknown"
        }
      end
    end

    {
      status: "success",
      added: added,
      total_count: added.map { |item| item[:chunk_count] || 1 }.sum
    }
  end

  # Unified similarity search
  def similarity_search(
    query:,
    limit: DEFAULT_LIMIT,
    collection: DEFAULT_COLLECTION,
    distance: DEFAULT_DISTANCE,
    mode: nil
  )
    Rails.logger.tagged("EmbeddingTool", "similarity_search") do
      service = EmbeddingService.new(collection: collection)
      results = service.similarity_search(query, k: limit, distance: distance)

      {
        status: "success",
        message: "Found #{results.count} similar documents",
        results: Array(results).map { |result| format_search_result(result) }
      }
    end
  end

  # RAG-based QA (wraps embedding service's ask)
  def ask(question:, limit: DEFAULT_LIMIT, collection: DEFAULT_COLLECTION)
    Rails.logger.tagged("EmbeddingTool", "ask") do
      similar = similarity_search(query: question, limit: limit, collection: collection)

      # Extract content from results for the prompt
      contents = similar[:results].map { |r| r[:content] }.join("\n\n")

      prompt = "Answer the question based on the following documents:\n\n#{contents}\n\nQuestion: #{question}"
      response = llm.chat(messages: [ { role: "user", content: prompt } ])
      answer = response.chat_completion

      # Log the LLM call if there's a method for it
      log_llm_call(question, response) if respond_to?(:log_llm_call, true)

      {
        status: "success",
        answer: answer,
        sources: similar[:results].map do |result|
          {
            content: result[:content],
            url: result[:source_url],
            title: result[:source_title]
          }
        end
      }
    end
  end

  private

  # Convert input to array, handling both single items and arrays
  def to_array(input)
    Array(input).compact
  end

  # Validate chunking parameters
  def validate_chunking_params(chunk_size, chunk_overlap)
    return unless chunk_size

    raise ArgumentError, "Chunk size must be greater than 0." if chunk_size <= 0
    raise ArgumentError, "Chunk overlap must be greater than or equal to 0." if chunk_overlap && chunk_overlap < 0
    raise ArgumentError, "Chunk size must be greater than chunk overlap." if chunk_overlap && chunk_size <= chunk_overlap
    raise ArgumentError, "Chunk size must be less than or equal to #{MAX_CHUNK_SIZE}" if chunk_size > MAX_CHUNK_SIZE
  end

  # Validate and open a file
  def validate_and_open_file(file)
    if file.is_a?(String)
      # Handle string file paths
      expanded_path = File.expand_path(file)
      raise ArgumentError, "File not found: #{file}" unless File.exist?(expanded_path)
      raise ArgumentError, "File is not readable: #{file}" unless File.readable?(expanded_path)
      raise ArgumentError, "File is empty or too small: #{file}" if File.size(expanded_path) < 10
      File.open(expanded_path)
    elsif file.respond_to?(:read)
      # Handle file-like objects
      if file.respond_to?(:path) && file.path && !file.path.empty?
        path = file.path
        # Only validate the path if it appears to be a real file path
        # (not a StringIO or other IO-like object with a non-file path)
        if File.exist?(path)
          raise ArgumentError, "File is not readable: #{path}" unless File.readable?(path)

          # Check if file is at beginning
          if file.respond_to?(:pos) && file.pos > 0
            file.rewind rescue nil
          end
        end
      end
      file
    else
      raise ArgumentError, "Unsupported file object: #{file.inspect}"
    end
  end

  private

# Generic metadata
def build_metadata(content_type: nil, source_url: nil, source_title: nil, extra: {})
  {
    content_type: content_type,
    source_url: source_url,
    source_title: source_title
  }.compact.merge(extra || {})
end

# File-specific metadata (for IO/File objects)
def build_file_metadata(file_obj, merge: {}, content_type: nil, source_url: nil, source_title: nil)
  metadata = {}
  metadata[:source_title]   = source_title if source_title
  metadata[:source_url]     = source_url if source_url

  # Extract file path information
  if file_obj.respond_to?(:path) && file_obj.path && !file_obj.path.empty?
    file_path = file_obj.path
    metadata[:source_title] ||= file_path
    metadata[:file_path]      = file_path
    metadata[:file_name]      = File.basename(file_path) rescue nil
    metadata[:file_ext]       = File.extname(file_path).downcase rescue nil
    metadata[:file_dir]       = File.dirname(file_path) rescue nil

    # Try to determine content type from extension if not provided
    if content_type.nil? && metadata[:file_ext]
      ext = metadata[:file_ext].downcase
      content_type = case ext
      when ".md", ".txt", ".text" then "text"
      when ".html", ".htm" then "html"
      when ".pdf" then "pdf"
      when ".doc", ".docx" then "document"
      when ".rb", ".py", ".js", ".java", ".c", ".cpp" then "code"
      when ".json", ".xml", ".yaml", ".yml" then "data"
      else "unknown"
      end
    end
  end

  # For IO objects without a path (like StringIO)
  if !metadata[:source_title] && !source_title
    metadata[:source_title] = "In-memory content"
  end

  metadata[:file_size]        = file_obj.size if file_obj.respond_to?(:size)
  metadata[:content_type]     = content_type ||
    (file_obj.respond_to?(:content_type) && file_obj.content_type) ||
    DEFAULT_CONTENT_TYPE
  metadata[:timestamp]        = Time.now.iso8601
  metadata[:io_class]         = file_obj.class.name

  # Merge any additional metadata
  metadata.merge!(file_obj.metadata) if file_obj.respond_to?(:metadata)
  metadata.merge!(merge || {})
  metadata.compact
end


  # Format search result for consistent output
  def format_search_result(result)
    metadata = result.respond_to?(:metadata) ? result.metadata : {}
    {
      id: result.respond_to?(:id) ? result.id : nil,
      content: extract_content(result, metadata),
      content_type: metadata[:content_type] || result.try(:content_type) || "unknown",
      source_url: metadata[:source_url] || result.try(:source_url),
      source_title: metadata[:source_title] || result.try(:source_title),
      metadata: metadata
    }
  end

  # Extract content from various result types
  def extract_content(result, metadata = {})
    metadata[:content] ||
      (result.respond_to?(:page_content) && result.page_content.to_s.truncate(MAX_CONTENT_PREVIEW)) ||
      (result.respond_to?(:content) && result.content.to_s.truncate(MAX_CONTENT_PREVIEW)) ||
      "Unknown content"
  end

  # Log LLM calls
  def log_llm_call(question, response)
    Rails.logger.tagged("EmbeddingTool", "llm_call") do
      Rails.logger.info("LLM call for question: #{question}")
    end
  end
end
