# Create initial prompt categories

puts "Creating prompt categories..."

# Define categories
categories = [
  {
    name: "Research",
    slug: "research",
    description: "Prompts for research tasks, information gathering, and analysis."
  },
  {
    name: "Code Analysis",
    slug: "code_analysis",
    description: "Prompts for analyzing, understanding, and documenting code."
  },
  {
    name: "Task Management",
    slug: "task_management",
    description: "Prompts for breaking down, planning, and managing tasks."
  },
  {
    name: "Coordination",
    slug: "coordination",
    description: "Prompts for coordinating between different agents and components."
  },
  {
    name: "Content Generation",
    slug: "content_generation",
    description: "Prompts for generating content, summaries, and reports."
  },
  {
    name: "System",
    slug: "system",
    description: "System-level prompts for core functionality."
  }
]

# Create categories
categories.each do |category_data|
  category = PromptCategory.find_or_initialize_by(slug: category_data[:slug])
  category.assign_attributes(category_data)

  if category.new_record?
    puts "  Creating category: #{category.name}"
  else
    puts "  Updating category: #{category.name}"
  end

  category.save!
end

puts "Prompt categories created successfully!"
