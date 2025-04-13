# Example of using pgvector with the Neighbor gem
# Run this example with:
# rails runner app/examples/vector_search_example.rb

# First, make sure we have some sample data
puts "Creating sample vector embeddings..."

# Clear out any existing embeddings in the test collection
VectorEmbedding.where(collection: "test").destroy_all

# Sample text documents
sample_texts = [
  "Ruby on Rails is a web application framework written in Ruby.",
  "PostgreSQL is a powerful, open source object-relational database system.",
  "pgvector is a PostgreSQL extension for vector similarity search.",
  "The Neighbor gem makes it easy to use vector search in Rails applications.",
  "Machine learning models can convert text and images into vectors called embeddings.",
  "Vector similarity search helps find content with similar meaning, not just keyword matches.",
  "Artificial intelligence is transforming how we build web applications.",
  "Natural language processing uses AI to understand human language.",
  "Rails 8 introduced many new features and performance improvements.",
  "Vector databases are specialized for storing and querying embedding vectors."
]

# Store each text with its embedding
sample_texts.each do |text|
  puts "Creating embedding for: #{text[0..50]}..."
  VectorEmbedding.store(
    content: text,
    content_type: "text",
    collection: "test",
    metadata: { source: "example" }
  )
end

puts "\nPerforming vector searches:"

# Search examples
search_queries = [
  "databases and PostgreSQL",
  "AI and machine learning",
  "pgvector extension",
  "Rails framework updates"
]

search_queries.each do |query|
  puts "\nSearch query: \"#{query}\""
  results = VectorEmbedding.search(
    text: query,
    limit: 3,
    collection: "test",
    distance: "cosine"
  )

  puts "Top 3 results:"
  results.each_with_index do |result, index|
    puts "#{index + 1}. #{result.content}"
    puts "   Distance: #{result.neighbor_distance.round(4)}"
  end
end

puts "\nExample complete!"
