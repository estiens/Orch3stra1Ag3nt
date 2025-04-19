namespace :prompts do
  desc "Import prompts from agent modules into the database"
  task import: :environment do
    puts "Importing prompts from agent modules..."

    # First, ensure categories exist
    Rake::Task["db:seed:prompt_categories"].invoke if PromptCategory.count == 0

    # Define modules and their categories
    module_mappings = [
      { module_name: "CodeResearcher::Prompts", category_slug: "code_analysis" },
      { module_name: "ResearchCoordinator::Prompts", category_slug: "research" },
      { module_name: "Coordinator::Prompts", category_slug: "coordination" }
    ]

    # Import prompts from each module
    total_imported = 0
    module_mappings.each do |mapping|
      begin
        puts "Processing module: #{mapping[:module_name]}"

        # Get the module
        mod = mapping[:module_name].constantize

        # Get prompt methods (ending with _prompt)
        prompt_methods = mod.instance_methods(false).select do |method_name|
          method_name.to_s.end_with?("_prompt")
        end

        puts "  Found #{prompt_methods.size} potential prompt methods"

        # Create prompts
        service = PromptService.new
        imported = []

        prompt_methods.each do |method_name|
          prompt = service.import_from_module(
            mapping[:module_name],
            method_name,
            category_slug: mapping[:category_slug]
          )

          if prompt
            imported << prompt
            puts "  Imported: #{prompt.name}"
          else
            puts "  Failed to import: #{method_name}"
          end
        end

        total_imported += imported.size
        puts "  Successfully imported #{imported.size} prompts from #{mapping[:module_name]}"

      rescue NameError => e
        puts "  Error: Module #{mapping[:module_name]} not found: #{e.message}"
      rescue => e
        puts "  Error importing prompts from #{mapping[:module_name]}: #{e.message}"
      end
    end

    puts "Import complete! Total prompts imported: #{total_imported}"
  end

  desc "List all prompts in the database"
  task list: :environment do
    puts "Prompts in the database:"
    puts "------------------------"

    categories = PromptCategory.includes(:prompts).order(:name)

    if categories.empty?
      puts "No prompt categories found."
      return
    end

    categories.each do |category|
      puts "\n#{category.name} (#{category.prompts.count} prompts)"
      puts "-" * (category.name.length + 2 + category.prompts.count.to_s.length + 9)

      category.prompts.order(:name).each do |prompt|
        version = prompt.current_version
        version_info = version ? "v#{version.version_number}" : "no versions"
        puts "  - #{prompt.name} (#{version_info}) [#{prompt.slug}]"
      end
    end

    puts "\nTotal: #{Prompt.count} prompts in #{PromptCategory.count} categories"
  end

  desc "Evaluate prompt performance"
  task evaluate: :environment do
    puts "Prompt Performance Report"
    puts "-----------------------"

    # Get prompts with evaluations
    prompts_with_evaluations = Prompt.joins(:prompt_evaluations).distinct.order(:name)

    if prompts_with_evaluations.empty?
      puts "No prompt evaluations found."
      return
    end

    prompts_with_evaluations.each do |prompt|
      evaluations = prompt.prompt_evaluations
      avg_score = evaluations.average(:score).to_f.round(2)
      count = evaluations.count
      success_rate = (evaluations.where("score >= ?", 0.7).count.to_f / count * 100).round(2)

      puts "\n#{prompt.name} (#{prompt.slug})"
      puts "  Evaluations: #{count}"
      puts "  Average score: #{avg_score}"
      puts "  Success rate: #{success_rate}%"

      # Show version performance if multiple versions exist
      versions = prompt.prompt_versions.order(:version_number)
      if versions.count > 1
        puts "  Version performance:"
        versions.each do |version|
          version_evals = version.prompt_evaluations
          next if version_evals.empty?

          v_avg = version_evals.average(:score).to_f.round(2)
          v_count = version_evals.count
          puts "    v#{version.version_number}: #{v_avg} (#{v_count} evals)"
        end
      end
    end
  end

  desc "Initialize seed data for prompts system"
  task setup: :environment do
    # Run migrations if needed
    puts "Checking for pending migrations..."
    migrations_output = `bin/rails db:migrate:status | grep down`
    if migrations_output.present?
      puts "Running pending migrations..."
      Rake::Task["db:migrate"].invoke
    else
      puts "No pending migrations."
    end

    # Create categories
    puts "Creating prompt categories..."
    Rake::Task["db:seed:prompt_categories"].invoke

    # Import prompts
    puts "Importing prompts from modules..."
    Rake::Task["prompts:import"].invoke

    puts "\nPrompt system setup complete!"
    puts "Run 'bin/rails prompts:list' to see imported prompts."
  end
end

# Add seed tasks
namespace :db do
  namespace :seed do
    desc "Seed prompt categories"
    task prompt_categories: :environment do
      load Rails.root.join("db/seeds/prompt_categories.rb")
    end
  end
end
