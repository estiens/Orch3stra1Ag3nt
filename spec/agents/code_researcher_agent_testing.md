# CodeResearcherAgent Testing Guide

This document provides guidance on testing the CodeResearcherAgent, which specializes in researching and understanding code-related questions.

## Test Files

- `spec/agents/code_researcher_agent_vcr_spec.rb`: Integration tests for the CodeResearcherAgent
- `spec/jobs/agents/code_researcher_agent_job_spec.rb`: Tests for the job that runs the CodeResearcherAgent

## VCR Configuration

The tests use VCR to record and replay HTTP interactions with external services like OpenRouter. This ensures tests are:

1. Fast (no actual API calls during subsequent test runs)
2. Deterministic (same results every time)
3. Able to run without network access or API keys after initial recording

VCR cassettes are stored in `spec/cassettes/` and named specifically for each test suite:

- `code_researcher_agent_integration.yml`
- `code_researcher_comprehensive_workflow.yml`
- `code_researcher_agent_job_integration.yml`
- `code_researcher_agent_job_error_handling.yml`

## Running the Tests

To run all the CodeResearcherAgent tests:

```bash
bundle exec rspec spec/agents/code_researcher_agent_vcr_spec.rb spec/jobs/agents/code_researcher_agent_job_spec.rb
```

To run a specific test file:

```bash
bundle exec rspec spec/agents/code_researcher_agent_vcr_spec.rb
```

To run a specific test:

```bash
bundle exec rspec spec/agents/code_researcher_agent_vcr_spec.rb:10 # Line number of the test
```

## Recording New Cassettes

If you need to re-record the VCR cassettes (e.g., when the API changes or you modify the agent's behavior):

1. Delete the existing cassette files:
   ```bash
   rm spec/cassettes/code_researcher_*.yml
   ```

2. Ensure you have a valid OpenRouter API key in your `.env` file:
   ```
   OPEN_ROUTER_API_KEY=your-api-key
   ```

3. Run the tests to record new cassettes:
   ```bash
   bundle exec rspec spec/agents/code_researcher_agent_vcr_spec.rb spec/jobs/agents/code_researcher_agent_job_spec.rb
   ```

## What the Tests Validate

### Integration Tests

The integration tests validate:

1. The agent's ability to make real API calls to OpenRouter
2. Core tool functionality:
   - Analyzing code questions
   - Explaining code
   - Taking notes
   - Compiling findings
3. The complete research workflow (with limited iterations)
4. Proper handling of OpenRouter API responses
5. Correct updating of task metadata and results

### Job Tests

The job tests validate:

1. Proper enqueuing of the CodeResearcherAgent job
2. Correct execution of the job and agent
3. Proper task state transitions
4. Error handling and reporting

## Security Considerations

- The VCR configuration filters out the OpenRouter API key from the recorded cassettes
- Sensitive information is replaced with placeholders like `<OPEN_ROUTER_API_KEY>`
- Always verify that API keys and other sensitive data are not included in the cassettes before committing them

## Extending the Tests

When adding new functionality to the CodeResearcherAgent, consider:

1. Adding specific tests for the new functionality
2. Extending the comprehensive workflow test to include the new functionality
3. Re-recording cassettes if necessary to capture new API interactions

Remember to keep the tests focused on real integration points rather than implementation details, as the agent's internal logic may change over time.