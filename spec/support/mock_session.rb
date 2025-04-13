# Mock session class for testing
class MockSession
  attr_reader :spans, :result
  
  def initialize(spans = [], result = nil)
    @spans = spans
    @result = result
  end
end

# Mock span class for testing
class MockSpan
  attr_reader :type, :arguments, :output
  
  def initialize(type, arguments, output)
    @type = type
    @arguments = arguments
    @output = output
  end
end
