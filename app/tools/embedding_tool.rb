# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

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
  DEFAULT_BATCH_SIZE = 20  # Default batch size for processing

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
    Dir.glob(File.join(directory, "**", "*")).select do |file|
      File.file?(file) && (pattern.nil? || File.fnmatch(pattern, File.basename(file)))
    end
  end

  def add_directory(directory, pattern: nil, content_type: nil, collection: DEFAULT_COLLECTION)
    # Validate directory
    Rails.logger.info("EmbeddingTool: Adding directory #{directory} with pattern #{pattern || 'none'} to collection '#{collection}'")
    validate_directory(directory)

    files = fetch_directory_files(directory, pattern)
    Rails.logger.info("EmbeddingTool: Found #{files.count} files matching the pattern")
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
    batch_size: DEFAULT_BATCH_SIZE # Process this many files at a time
  )
    # Validate parameters
    validate_chunking_params(chunk_size, chunk_overlap)

    # Initialize service and normalize input
    Rails.logger.info("EmbeddingTool: Processing #{files.size} files in collection '#{collection}' with batch size #{batch_size}")
    service = EmbeddingService.new(collection: collection)
    files_array = to_array(files)
    raise ArgumentError, "You must supply at least one file." if files_array.empty?

    # Process files in batches to manage memory usage
    process_files_in_batches(
      files_array,
      service,
      content_type,
      collection,
      chunk_size,
      chunk_overlap,
      source_url,
      source_title,
      metadata,
      batch_size
    )
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
    Rails.logger.info("EmbeddingTool: Adding #{texts.size} texts to collection '#{collection}'#{chunk_size ? " with chunking (size: #{chunk_size}, overlap: #{chunk_overlap || 0})" : ''}")
    service = EmbeddingService.new(collection: collection)
    items = to_array(texts)
    raise ArgumentError, "You must supply at least one text." if items.empty?

    # Process each text
    added = []
    items.each_with_index do |text, index|
      Rails.logger.debug("EmbeddingTool: Processing text #{index + 1}/#{items.size} (#{text.bytesize} bytes)")
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
        Rails.logger.info("EmbeddingTool: Document #{index + 1} chunked into #{embeddings.count} segments and embedded")
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
        Rails.logger.info("EmbeddingTool: Text #{index + 1} embedded with ID #{embedding&.id || 'unknown'}")
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
      Rails.logger.info("Searching collection '#{collection}' for: #{query.truncate(100)} (limit: #{limit}, distance: #{distance})")

      begin
        service = EmbeddingService.new(collection: collection)
        
        # Use the service's similarity_search method which properly handles the embedding format
        # and uses the Neighbor gem's methods correctly
        results = service.similarity_search(query, k: limit, distance: distance)
        
        Rails.logger.info("Found #{results.count} similar documents")

        {
          status: "success",
          message: "Found #{results.count} similar documents",
          results: Array(results).map { |result| format_search_result(result) }
        }
      rescue => e
        Rails.logger.error("Error in similarity search: #{e.message}")
        {
          status: "error",
          message: "Search failed: #{e.message}",
          results: []
        }
      end
    end
  end

  # RAG-based QA (wraps embedding service's ask)
  def ask(question:, limit: DEFAULT_LIMIT, collection: DEFAULT_COLLECTION)
    Rails.logger.tagged("EmbeddingTool", "ask") do
      Rails.logger.info("RAG QA on collection '#{collection}': #{question.truncate(100)} (retrieving #{limit} docs)")
      similar = similarity_search(query: question, limit: limit, collection: collection)

      # Extract content from results for the prompt
      contents = similar[:results].map { |r| r[:content] }.join("\n\n")
      Rails.logger.info("Retrieved #{similar[:results].size} documents for context")

      prompt = "Answer the question based on the following documents:\n\n#{contents}\n\nQuestion: #{question}"
      Rails.logger.debug("Sending prompt to LLM (#{prompt.bytesize} bytes)")
      response = llm.chat(messages: [ { role: "user", content: prompt } ])
      answer = response.chat_completion
      Rails.logger.info("Generated answer (#{answer.bytesize} bytes)")

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

  # Process files in batches to manage memory usage
  def process_files_in_batches(files_array, service, content_type, collection, chunk_size,
                              chunk_overlap, source_url, source_title, metadata, batch_size)
    added = []
    total_files = files_array.size
    start_time = Time.now
    processed_count = 0
    success_count = 0

    # Process files in batches to manage memory
    files_array.each_slice(batch_size).with_index do |batch, batch_idx|
      batch_num = batch_idx + 1
      batch_count = (total_files.to_f / batch_size).ceil
      batch_start = Time.now

      Rails.logger.info("EmbeddingTool: Processing batch #{batch_num}/#{batch_count} (#{batch.size} files)")

      # Prepare file data
      file_data = batch.map do |file|
        prepare_file_data(file, content_type, source_url, source_title, metadata)
      end

      # Filter out files with errors
      valid_files = file_data.select { |f| !f[:error] }
      error_files = file_data.select { |f| f[:error] }

      if error_files.any?
        Rails.logger.warn("EmbeddingTool: #{error_files.size}/#{batch.size} files had errors in batch #{batch_num}")
      end

      # Process valid files
      batch_results = []
      batch_results.concat(error_files) # Add error files to results

      # Process each file with the service
      if valid_files.any?
        Rails.logger.info("EmbeddingTool: Processing #{valid_files.size} valid files from batch #{batch_num}")

        valid_results = valid_files.map do |file|
          result = process_single_file(file, service, chunk_size, chunk_overlap)
          processed_count += 1
          success_count += 1 if result[:status] == "success"

          # Log progress periodically
          if processed_count % 5 == 0 || processed_count == total_files
            elapsed = Time.now - start_time
            rate = processed_count / [ elapsed, 0.1 ].max
            Rails.logger.info("EmbeddingTool: Progress - #{processed_count}/#{total_files} files processed (#{rate.round(2)} files/sec)")
          end

          result
        end

        batch_results.concat(valid_results)
        Rails.logger.info("EmbeddingTool: Successfully processed #{valid_results.count { |r| r[:status] == 'success' }}/#{valid_files.size} files in batch #{batch_num}")
      end

      # Add batch results to overall results
      added.concat(batch_results)

      batch_time = Time.now - batch_start
      files_per_second = batch.size / [ batch_time, 0.1 ].max
      Rails.logger.info("EmbeddingTool: Batch #{batch_num} completed in #{batch_time.round(2)}s (#{files_per_second.round(2)} files/sec)")
    end

    total_time = Time.now - start_time
    overall_rate = total_files / [ total_time, 0.1 ].max

    Rails.logger.info("EmbeddingTool: Completed processing all batches in #{total_time.round(2)}s. Success: #{success_count}/#{total_files} files (#{overall_rate.round(2)} files/sec)")

    {
      status: "success",
      message: "Files processed successfully",
      added: added,
      total_count: added.count,
      successful_count: success_count,
      duration_seconds: total_time.round(2),
      files_per_second: overall_rate.round(2)
    }
  end

  # Process a single file
  def process_single_file(file, service, chunk_size, chunk_overlap)
    begin
      # Measure processing time
      start_time = Time.now
      file_path = file[:path] || "unknown"
      file_size = file[:size] || 0

      Rails.logger.debug("EmbeddingTool: Started processing file #{file_path} (#{file_size} bytes)")

      # Process the file with the embedding service
      # Wrap in Timeout to prevent infinite hangs
      result = Timeout.timeout(300) do  # 5 minute timeout
        service.add_document(
          file[:content],
          chunk_size: chunk_size,
          chunk_overlap: chunk_overlap,
          content_type: file[:content_type],
          source_url: file[:source_url],
          source_title: file[:source_title],
          metadata: file[:metadata]
        )
      end

      process_time = Time.now - start_time
      Rails.logger.debug("EmbeddingTool: Completed processing file #{file_path} in #{process_time.round(2)}s - generated #{result.count} chunks")

      # Return the result
      {
        path: file_path,
        size: file_size,
        content_type: file[:content_type],
        chunk_preview: result.first&.content&.first(40),
        chunks: result.count,
        status: "success",
        duration_seconds: process_time.round(2)
      }
    rescue Timeout::Error => e
      Rails.logger.error("EmbeddingTool: Timeout processing file #{file[:path]} after 300s")
      {
        path: file[:path],
        error: "Processing timeout: operation took too long",
        status: "error"
      }
    rescue => e
      Rails.logger.error("EmbeddingTool: Error processing file #{file[:path]}: #{e.message}")
      {
        path: file[:path],
        error: "Processing error: #{e.message}",
        status: "error"
      }
    end
  end

  # Prepare file data for processing
  def prepare_file_data(file, content_type, source_url, source_title, metadata)
    begin
      file_obj = validate_and_open_file(file)
      file_path = file_obj.respond_to?(:path) ? file_obj.path : "unknown"

      # Determine content type if not provided
      detected_content_type = detect_content_type(file_obj, content_type)

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
        # Make sure we're at the beginning of the file
        file_obj.rewind if file_obj.respond_to?(:rewind)
        file_content = file_obj.read

        # Return a hash with all the data needed for processing
        {
          content: file_content,
          path: file_path,
          size: file_obj.respond_to?(:size) ? file_obj.size : file_content.size,
          content_type: detected_content_type,
          metadata: file_metadata,
          source_url: source_url || file_path,
          source_title: source_title || (file_obj.respond_to?(:path) && file_obj.path ? File.basename(file_obj.path) : "In-memory content")
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

  # Detect content type from file extension
  def detect_content_type(file_obj, content_type)
    return content_type if content_type

    if file_obj.respond_to?(:path) && file_obj.path
      ext = File.extname(file_obj.path).downcase
      case ext
      when ".md", ".txt", ".text" then "text"
      when ".html", ".htm" then "html"
      when ".pdf" then "pdf"
      when ".doc", ".docx" then "document"
      when ".rb", ".py", ".js", ".java", ".c", ".cpp" then "code"
      when ".json", ".xml", ".yaml", ".yml" then "data"
      else DEFAULT_CONTENT_TYPE
      end
    else
      DEFAULT_CONTENT_TYPE
    end
  end

  # Validate directory exists and is readable
  def validate_directory(directory)
    raise ArgumentError, "Directory not found: #{directory}" unless File.directory?(directory)
    raise ArgumentError, "Directory is not readable: #{directory}" unless File.readable?(directory)
  end

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
      validate_file_path(expanded_path)
      File.open(expanded_path)
    elsif file.respond_to?(:read)
      # Handle file-like objects (File, StringIO, etc.)
      validate_file_object(file)
      file
    else
      raise ArgumentError, "Unsupported file object: #{file.inspect}"
    end
  end

  # Validate a file path
  def validate_file_path(path)
    raise ArgumentError, "File not found: #{path}" unless File.exist?(path)
    raise ArgumentError, "File is not readable: #{path}" unless File.readable?(path)
    raise ArgumentError, "File is empty or too small: #{path}" if File.size(path) < 10
  end

  # Validate a file-like object
  def validate_file_object(file)
    if file.respond_to?(:path) && file.path && !file.path.empty?
      path = file.path
      # Only validate the path if it appears to be a real file path
      if File.exist?(path)
        raise ArgumentError, "File is not readable: #{path}" unless File.readable?(path)
      end
    end

    # Ensure we're at the beginning of the file
    file.rewind if file.respond_to?(:rewind)
  end

  # Generic metadata builder
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
