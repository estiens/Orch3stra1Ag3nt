# frozen_string_literal: true

# Example script demonstrating RAG (Retrieval Augmented Generation) with LangchainRB and pgvector
#
# This example shows how to:
# 1. Create an embedding service
# 2. Add documents to the vector database
# 3. Perform similarity search
# 4. Use RAG for question answering
#
# To run this example:
# rails runner app/examples/rag_example.rb

# Sample data
recipe_texts = [
  "Begin by preheating your oven to 375°F (190°C). Prepare four boneless, skinless chicken breasts by cutting a pocket into the side of each breast, being careful not to cut all the way through. Season the chicken with salt and pepper to taste. In a large skillet, melt 2 tablespoons of unsalted butter over medium heat. Add 1 small diced onion and 2 minced garlic cloves, and cook until softened, about 3-4 minutes. Add 8 ounces of fresh spinach and cook until wilted, about 3 minutes. Remove the skillet from heat and let the mixture cool slightly.",

  "In a bowl, combine the spinach mixture with 4 ounces of softened cream cheese, 1/4 cup of grated Parmesan cheese, 1/4 cup of shredded mozzarella cheese, and 1/4 teaspoon of red pepper flakes. Mix until well combined. Stuff each chicken breast pocket with an equal amount of the spinach mixture. Seal the pocket with a toothpick if necessary. In the same skillet, heat 1 tablespoon of olive oil over medium-high heat. Add the stuffed chicken breasts and sear on each side for 3-4 minutes, or until golden brown.",

  "To make classic chocolate chip cookies, preheat your oven to 350°F (175°C). In a large bowl, cream together 1 cup of softened butter, 1 cup of white sugar, and 1 cup of packed brown sugar until smooth. Beat in 2 eggs one at a time, then stir in 2 teaspoons of vanilla extract. Dissolve 1 teaspoon of baking soda in 2 teaspoons of hot water and add to the batter along with 1/2 teaspoon of salt. Stir in 3 cups of all-purpose flour and 2 cups of chocolate chips. Drop by large spoonfuls onto ungreased baking sheets and bake for about 10 minutes or until edges are nicely browned.",

  "For a refreshing summer salad, combine 2 cups of diced watermelon, 1 cup of crumbled feta cheese, 1/2 cup of thinly sliced red onion, and 1/4 cup of chopped fresh mint leaves in a large bowl. In a small bowl, whisk together 2 tablespoons of olive oil, 2 tablespoons of fresh lime juice, 1 tablespoon of honey, and salt and pepper to taste. Drizzle the dressing over the salad and toss gently to combine. Serve immediately for the best flavor and texture."
]

puts "=== RAG Example with LangchainRB and pgvector ==="
puts

# Create an embedding service for recipes
puts "Creating embedding service..."
embedding_service = EmbeddingService.new(collection: "recipes")

# Add recipe texts to the vector database
puts "Adding recipe texts to vector database..."
embeddings = embedding_service.add_texts(recipe_texts, content_type: "recipe")
puts "Added #{embeddings.count} recipe embeddings to the database"
puts

# Perform similarity search
query = "How do I make chicken with cheese?"
puts "Performing similarity search for: '#{query}'"
results = embedding_service.similarity_search(query, k: 2)
puts "Top 2 similar recipes:"
results.each_with_index do |result, index|
  puts "#{index + 1}. #{result.content[0..100]}..."
end
puts

# Use RAG for question answering
puts "Using RAG for question answering..."
questions = [
  "What temperature should I preheat the oven for chicken?",
  "What ingredients are in the chocolate chip cookies?",
  "How do I make the dressing for the watermelon salad?"
]

questions.each do |question|
  puts "\nQuestion: #{question}"
  result = embedding_service.ask(question, k: 3)
  puts "Answer: #{result[:answer]}"
  puts "Sources:"
  result[:sources].each_with_index do |source, index|
    puts "  #{index + 1}. #{source[:content]}..."
  end
end

puts "\n=== Example Complete ==="

# Example of using HyDE (Hypothetical Document Embeddings)
puts "\n=== Using HyDE for improved semantic search ==="
query = "What's a good summer dish to bring to a picnic?"
puts "Query: #{query}"
results = embedding_service.similarity_search_with_hyde(query, k: 1)
puts "HyDE Result:"
puts results.first.content[0..200] + "..."
puts "\n=== HyDE Example Complete ==="
