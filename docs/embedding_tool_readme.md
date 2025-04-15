# Hugging Face Embedding Tool with PostgreSQL Vector Storage

This document explains how to use the Hugging Face embedding functionality with PostgreSQL vector storage for building Retrieval Augmented Generation (RAG) applications.

## Overview

The embedding system provides functionality to:

1. Generate embeddings using Hugging Face API
2. Store embeddings in PostgreSQL using the neighbor gem
3. Retrieve similar content through vector similarity search
4. Implement RAG for question answering

## Components

### 1. EmbeddingService
Located at `app/services/embedding_service.rb`, this service provides the core functionality:

- Generate embeddings with Hugging Face API
- Store content with embeddings in PostgreSQL using ActiveRecord
- Perform similarity search with the neighbor gem
- Implement chunking for documents
- Collection-based organization of embeddings
- Task and project associations
- Support for file parsing and embedding
- Basic implementation of HyDE (Hypothetical Document Embeddings)
- RAG-based question answering

### 2. EmbeddingTool

Located at `app/tools/embedding_tool.rb`, this tool provides a Langchain-compatible interface:

- Implements Langchain's ToolDefinition interface
- Defines schemas for each function, making it usable by LLMs
- Formats responses in a standardized way for LLM consumption
- Delegates operations to EmbeddingService

## Database Schema

The system uses the `vector_embeddings` table with the following schema:

```ruby
create_table :vector_embeddings do |t|
  t.references :task, null: true, foreign_key: true, index: true
  t.references :project, null: true, foreign_key: true, index: true
  t.string :collection, null: false, default: 'default'  # Collection/namespace
  t.string :content_type, null: false, default: 'text'   # text, url, code, etc.
  t.text :content, null: false                           # Actual content
  t.string :source_url                                   # URL source if available
  t.string :source_title                                 # Title of the source
  t.jsonb :metadata, null: false, default: {}            # Additional metadata
  t.vector :embedding, limit: 1536, null: false          # Vector embedding
  t.timestamps
end
```

## Usage Examples

### Basic Usage

```ruby
# Create an embedding service
embedding_service = EmbeddingService.new(collection: "my_collection")

# Add a single text
embedding_service.add_text("This is some text to embed")

# Add multiple texts
texts = ["Text 1", "Text 2", "Text 3"]
embedding_service.add_texts(texts)

# Search for similar content
results = embedding_service.similarity_search("Find content similar to this")

# Ask a question using RAG
answer = embedding_service.ask("What is the capital of France?")
```

### Advanced Usage

#### Working with Documents

```ruby
# Add a document with chunking
embedding_service.add_document(
  long_text,
  chunk_size: 1000,
  chunk_overlap: 200,
  content_type: "article",
  source_url: "https://example.com/article",
  source_title: "Example Article",
  metadata: { author: "John Doe", date: "2025-04-14" }
)

# Add documents from files
file_paths = ["document.pdf", "article.docx", "data.txt"]
embedding_service.add_data(file_paths)
```

#### Using HyDE for Improved Retrieval

```ruby
# Use HyDE for semantic search
results = embedding_service.similarity_search_with_hyde(
  "What's a good recipe for vegetarians?",
  k: 5
)
```

## RAG (Retrieval Augmented Generation)

RAG combines retrieval of relevant documents with generation from an LLM. The workflow is:

1. Convert a user query into an embedding
2. Retrieve relevant documents from the vector database
3. Combine the query and retrieved documents into a prompt
4. Send the prompt to an LLM to generate a response

This approach helps ground LLM responses in factual information and reduces hallucinations.

### Example RAG Implementation

```ruby
# Ask a question using RAG
result = embedding_service.ask("How do I make chocolate chip cookies?")

# The result contains both the answer and the sources
puts result[:answer]
puts result[:sources]
```

## Complete Example

See `app/examples/rag_example.rb` for a complete example of using the embedding service and Langchain tool.

## Customization

### Hugging Face Embedding Configuration

You can configure the Hugging Face embedding endpoint and API token:

```ruby
# Set the Hugging Face API token
ENV["HUGGINGFACE_API_TOKEN"] = "your-huggingface-api-token"

# Optionally set a custom endpoint (defaults to https://piujqyd9p0cdbgx1.us-east4.gcp.endpoints.huggingface.cloud)
ENV["HUGGINGFACE_EMBEDDING_ENDPOINT"] = "https://your-custom-endpoint.huggingface.cloud"

# Create the embedding service
embedding_service = EmbeddingService.new(collection: "my_collection")

# Generate an embedding directly
embedding = embedding_service.generate_embedding("Generate embedding for this text")
```

The system uses the neighbor gem for vector search, which provides efficient nearest neighbor search capabilities for PostgreSQL. It directly integrates with ActiveRecord to store and retrieve embeddings.

### Integration with LLMs

In a production system, you would integrate this with an LLM for the RAG implementation:

```ruby
# Get similar documents
similar_docs = embedding_service.similarity_search("Your query here", k: 5)

# Format them into a prompt
prompt = "Answer this question based on the following context:\n\n"
similar_docs.each do |doc|
  prompt += "#{doc.content}\n\n"
end
prompt += "Question: What are the key points?"

# Send to your preferred LLM
# response = your_llm_client.generate(prompt)
```

## Using the EmbeddingTool

The `EmbeddingTool` implements Langchain's ToolDefinition interface, making it usable by LLMs and agent frameworks. Here's how to use it directly:

```ruby
# Initialize the Langchain tool
embedding_tool = EmbeddingTool.new

# Add a document
result = embedding_tool.add(
  texts: ["This is a long document that will be chunked automatically..."],
  collection: "agent_knowledge",
  chunk_size: 1000,
  chunk_overlap: 200,
  source_url: "https://example.com/document",
  source_title: "Example Document"
)

# Search for similar content
search_result = embedding_tool.similarity_search(
  query: "What does the document say about examples?",
  limit: 3,
  collection: "agent_knowledge"
)

# Ask a question using RAG
answer = embedding_tool.ask(
  question: "Can you summarize the key points?",
  collection: "agent_knowledge"
)

# Access the answer and sources
puts answer[:answer]
puts answer[:sources]
```
## Performance Considerations

- For large datasets, consider using batched operations to add embeddings
- Use appropriate chunk sizes for your content (smaller for precise retrieval, larger for more context)
- Adjust the distance metric based on your use case (cosine, euclidean, inner_product)
- Use the HNSW index for faster similarity search on large datasets

## Environment Variables

The embedding system uses the following environment variables:

- `DATABASE_URL`: Connection string for the PostgreSQL database
- `HUGGINGFACE_API_TOKEN`: API token for Hugging Face (used for embeddings)
- `HUGGINGFACE_EMBEDDING_ENDPOINT`: Optional custom endpoint for Hugging Face embedding API