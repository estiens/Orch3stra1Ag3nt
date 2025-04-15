# LangchainRB Embedding Tool with PostgreSQL Vector Storage

This document explains how to use the LangchainRB embedding tool and service with PostgreSQL vector storage for building Retrieval Augmented Generation (RAG) applications.

## Overview

The embedding tool provides functionality to:

1. Generate embeddings using LangchainRB
2. Store embeddings in PostgreSQL using pgvector
3. Retrieve similar content through vector similarity search
4. Implement RAG for question answering

## Components

### 1. EmbeddingTool

Located at `app/tools/embedding_tool.rb`, this tool provides low-level functionality:

- Generate embeddings with LangchainRB
- Store content with embeddings
- Perform similarity search
- Implement chunking for documents
- Basic RAG for question answering

### 2. EmbeddingService

Located at `app/services/embedding_service.rb`, this service provides a higher-level API:

- Collection-based organization of embeddings
- Task and project associations
- Methods for adding single texts, multiple texts, and documents
- Support for file parsing and embedding
- Similarity search with various parameters
- HyDE (Hypothetical Document Embeddings) for improved retrieval
- RAG-based question answering

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

See `app/examples/rag_example.rb` for a complete example of using the embedding tool and service.

## Customization

### Using Different Embedding Models

You can customize the embedding model when creating the service:

```ruby
# Use a different embedding model
custom_embedding = Langchain::Embeddings::OpenAI.new(
  api_key: ENV["OPENAI_API_KEY"],
  model_name: "text-embedding-3-large"
)

embedding_service = EmbeddingService.new(
  collection: "my_collection",
  llm: custom_embedding
)
```

### Using Different LLMs for Generation

You can customize the LLM used for generation:

```ruby
# Use a different LLM
custom_llm = Langchain::LLM::OpenAI.new(
  api_key: ENV["OPENAI_API_KEY"],
  default_options: { chat_model: "gpt-4" }
)

embedding_service = EmbeddingService.new(
  collection: "my_collection",
  llm: custom_llm
)
```

## Performance Considerations

- For large datasets, consider using batched operations to add embeddings
- Use appropriate chunk sizes for your content (smaller for precise retrieval, larger for more context)
- Adjust the distance metric based on your use case (cosine, euclidean, inner_product)
- Use the HNSW index for faster similarity search on large datasets