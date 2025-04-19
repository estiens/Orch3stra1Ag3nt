# frozen_string_literal: true

module ResearchCoordinator
  module Prompts
    def analyze_research_question_prompt(research_question)
      <<~PROMPT
        Break down the following research question into specific, actionable research tasks:

        RESEARCH QUESTION: #{research_question}

        Provide 3-5 focused subtasks with:
        1. Research focus
        2. Suggested methods/sources
        3. Contribution to the overall question

        FORMAT:
        Research Task 1: [FOCUS]
        Methods: [METHODS/SOURCES]
        Contribution: [CONTRIBUTION]
        ...

        Finally, provide a brief research plan (order and rationale).
      PROMPT
    end

    def consolidate_findings_prompt(task_title, findings)
      <<~PROMPT
        Synthesize findings from multiple research tasks into a coherent summary.

        OVERALL RESEARCH QUESTION: #{task_title}

        INDIVIDUAL FINDINGS:
        #{findings}

        Synthesize these findings into a comprehensive summary addressing the original question.
        Highlight key conclusions, contradictions, and remaining gaps.

        FORMAT:
        SUMMARY:
        [Comprehensive summary]

        KEY INSIGHTS:
        - [Insight 1]

        CONTRADICTIONS/UNCERTAINTIES:
        - [Contradiction 1]

        GAPS/NEXT STEPS:
        - [Gap 1]
      PROMPT
    end

    def parse_research_subtasks_prompt(analysis)
      <<~PROMPT
        Parse the following research task analysis into structured data:

        ANALYSIS:
        #{analysis}

        Extract each research task with:
        1. Title
        2. Description
        3. Methods/sources

        FORMAT EACH TASK AS:
        {
          "title": "Task title",
          "description": "Detailed task description",
          "methods": ["method1", "method2"]
        }

        Return a JSON array of task objects.
      PROMPT
    end
  end
end
