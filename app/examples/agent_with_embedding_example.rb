# frozen_string_literal: true

# Example script demonstrating how to use the embedding tool with agents
#
# This example shows how to:
# 1. Create an agent that uses the embedding tool
# 2. Store knowledge in the vector database
# 3. Have the agent retrieve and use that knowledge
#
# To run this example:
# rails runner app/examples/agent_with_embedding_example.rb

class KnowledgeAgent < BaseAgent
  # Define the purpose of this agent
  def self.description
    "An agent that can store and retrieve knowledge using vector embeddings"
  end

  # Register custom tools
  def self.custom_tool_objects
    [
      LangchainEmbeddingTool.new
    ]
  end

  # Define a tool for storing knowledge
  tool :store_knowledge, "Store knowledge in the vector database" do |text, collection: "knowledge"|
    # Use the embedding tool to store the knowledge
    execute_tool(:add_text, text: text, collection: collection)
    "Knowledge stored successfully: #{text.truncate(50)}"
  end

  # Define a tool for retrieving knowledge
  tool :retrieve_knowledge, "Retrieve knowledge from the vector database" do |query, collection: "knowledge", limit: 3|
    # Use the embedding tool to retrieve the knowledge
    results = execute_tool(:similarity_search, query: query, collection: collection, limit: limit)

    if results[:results].empty?
      "No relevant knowledge found for: #{query}"
    else
      "Found relevant knowledge:\n\n" +
      results[:results].map.with_index do |result, i|
        "#{i+1}. #{result[:content]}"
      end.join("\n\n")
    end
  end

  # Define a tool for answering questions using RAG
  tool :answer_question, "Answer a question using RAG" do |question, collection: "knowledge"|
    # Use the embedding tool to answer the question
    result = execute_tool(:ask, question: question, collection: collection)

    "Answer: #{result[:answer]}\n\n" +
    "Sources:\n" +
    result[:sources].map.with_index do |source, i|
      "#{i+1}. #{source[:content] || 'N/A'}"
    end.join("\n")
  end

  # Main execution method
  def run(input = nil)
    before_run(input)

    # Parse the input
    collection = input[:collection] || "knowledge"
    action = input[:action]

    result = case action
    when "store"
      # Store knowledge
      text = input[:text]
      execute_tool(:store_knowledge, text, collection: collection)

    when "retrieve"
      # Retrieve knowledge
      query = input[:query]
      execute_tool(:retrieve_knowledge, query, collection: collection)

    when "answer"
      # Answer a question
      question = input[:question]
      execute_tool(:answer_question, question, collection: collection)

    else
      "Unknown action: #{action}. Available actions: store, retrieve, answer"
    end

    @session_data[:output] = result
    after_run(result)
    result
  end
end

puts "=== Knowledge Agent with Embedding Tool Example ==="
puts

# Create a knowledge agent
agent = KnowledgeAgent.new(purpose: "Demonstrate embedding tool with agents")

# Sample knowledge
knowledge = [
  "Ruby is a dynamic, open source programming language with a focus on simplicity and productivity. It has an elegant syntax that is natural to read and easy to write.",

  "Ruby on Rails is a web application framework written in Ruby. It is designed to make programming web applications easier by making assumptions about what every developer needs to get started.",

  "PostgreSQL is a powerful, open source object-relational database system with over 35 years of active development. It is known for reliability, feature robustness, and performance.",

  "Vector embeddings are mathematical representations of data (like text) in a high-dimensional space. They capture semantic meaning, allowing for operations like similarity search."
]

# Store knowledge
puts "Storing knowledge..."
knowledge.each do |text|
  result = agent.run(action: "store", text: text, collection: "demo_knowledge")
  puts result
end
puts

# Retrieve knowledge
puts "Retrieving knowledge about Ruby..."
result = agent.run(action: "retrieve", query: "What is Ruby?", collection: "demo_knowledge")
puts result
puts

# Retrieve knowledge
puts "Retrieving knowledge about databases..."
result = agent.run(action: "retrieve", query: "Tell me about PostgreSQL", collection: "demo_knowledge")
puts result
puts

# Answer a question
puts "Answering a question using RAG..."
result = agent.run(action: "answer", question: "What is Ruby on Rails?", collection: "demo_knowledge")
puts result
puts

puts "=== Example Complete ==="
