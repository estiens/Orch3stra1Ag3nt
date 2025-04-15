# frozen_string_literal: true

# Example script demonstrating how to use langchainrb with pgvector
#
# This example shows how to:
# 1. Initialize a pgvector client
# 2. Create the default schema
# 3. Add texts to the vector database
# 4. Add documents from files
# 5. Perform similarity searches
# 6. Use RAG for question answering
#
# To run this example:
# rails runner app/examples/langchain_pgvector_example.rb

puts "=== LangchainRB with Pgvector Example ==="
puts

# Initialize the pgvector client
client = Langchain::Vectorsearch::Pgvector.new(
  connection_string: ENV["DATABASE_URL"],
  schema_name: "vector_search",
  table_name: "example_collection"
  # pgvector will use the default embedding model
)

puts "1. Creating the default schema..."
# Create the default schema
client.create_default_schema
puts "Schema created successfully."
puts

puts "2. Adding plain text data to the vector database..."
# Add plain text data to the vector database
texts = [
  "Begin by preheating your oven to 375°F (190°C). Prepare four boneless, skinless chicken breasts by cutting a pocket into the side of each breast, being careful not to cut all the way through. Season the chicken with salt and pepper to taste. In a large skillet, melt 2 tablespoons of unsalted butter over medium heat. Add 1 small diced onion and 2 minced garlic cloves, and cook until softened, about 3-4 minutes. Add 8 ounces of fresh spinach and cook until wilted, about 3 minutes. Remove the skillet from heat and let the mixture cool slightly.",
  "In a bowl, combine the spinach mixture with 4 ounces of softened cream cheese, 1/4 cup of grated Parmesan cheese, 1/4 cup of shredded mozzarella cheese, and 1/4 teaspoon of red pepper flakes. Mix until well combined. Stuff each chicken breast pocket with an equal amount of the spinach mixture. Seal the pocket with a toothpick if necessary. In the same skillet, heat 1 tablespoon of olive oil over medium-high heat. Add the stuffed chicken breasts and sear on each side for 3-4 minutes, or until golden brown."
]

result = client.add_texts(
  texts: texts,
  metadatas: [
    { source: "Recipe Book", category: "Main Dish" },
    { source: "Recipe Book", category: "Main Dish" }
  ]
)
puts "Added #{texts.size} texts to the database."
puts

# Example of file paths
puts "3. Example of loading files (commented out)..."
puts "# Uncomment and use real file paths for this functionality"
# my_pdf = Langchain.root.join("path/to/my.pdf")
# my_text = Langchain.root.join("path/to/my.txt")
# my_docx = Langchain.root.join("path/to/my.docx")
#
# client.add_data(paths: [my_pdf, my_text, my_docx])
puts "Supported file formats: docx, html, pdf, text, json, jsonl, csv, xlsx, eml, pptx."
puts

puts "4. Performing similarity search based on query string..."
# Retrieve similar documents based on the query string
results = client.similarity_search(
  query: "How do I prepare chicken?",
  k: 2
)

puts "Found #{results.size} similar documents:"
results.each_with_index do |doc, i|
  puts "#{i+1}. #{doc.page_content.truncate(100)}"
  puts "   Metadata: #{doc.metadata.inspect}"
  puts
end

puts "5. Performing similarity search with HyDE technique..."
# Retrieve similar documents using HyDE technique
hyde_results = client.similarity_search_with_hyde(
  query: "What ingredients do I need for the recipe?",
  k: 2
)

puts "Found #{hyde_results.size} similar documents using HyDE:"
hyde_results.each_with_index do |doc, i|
  puts "#{i+1}. #{doc.page_content.truncate(100)}"
  puts "   Metadata: #{doc.metadata.inspect}"
  puts
end

puts "6. Generating an embedding for a query and searching by vector..."
# Generate an embedding for a query
query_embedding = client.embedding.embed_query("How to cook chicken with spinach?")

# Retrieve similar documents based on the embedding
vector_results = client.similarity_search_by_vector(
  embedding: query_embedding,
  k: 2
)

puts "Found #{vector_results.size} similar documents by vector:"
vector_results.each_with_index do |doc, i|
  puts "#{i+1}. #{doc.page_content.truncate(100)}"
  puts "   Metadata: #{doc.metadata.inspect}"
  puts
end

puts "7. RAG-based querying..."
# RAG-based querying
answer = client.ask(question: "What temperature should I preheat the oven to?")

puts "Question: What temperature should I preheat the oven to?"
puts "Answer: #{answer.answer}"
puts
puts "Sources:"
answer.source_documents.each_with_index do |doc, i|
  puts "#{i+1}. #{doc.page_content.truncate(100)}"
  puts
end

puts "=== Example Complete ==="
