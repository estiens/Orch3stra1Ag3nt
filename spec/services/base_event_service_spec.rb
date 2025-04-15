require 'rails_helper'

RSpec.describe BaseEventService do
  let(:service) { BaseEventService.new }
  let(:event) { create(:event, event_type: 'test.event') }
  let(:handler_name) { 'TestHandler' }
  
  describe '#log_event_processing' do
    it 'logs the event being processed' do
      expect(service.logger).to receive(:info).with("#{handler_name} processing event: #{event.event_type} [#{event.id}]")
      service.log_event_processing(event, handler_name)
    end
  end
  
  describe '#log_event_success' do
    it 'logs successful event handling without result' do
      expect(service.logger).to receive(:info).with("#{handler_name} successfully processed event: #{event.event_type} [#{event.id}]")
      service.log_event_success(event, handler_name)
    end
    
    it 'logs successful event handling with result' do
      result = { status: 'success' }
      expect(service.logger).to receive(:info)
      expect(service.logger).to receive(:debug).with("#{handler_name} result: #{result.inspect}")
      service.log_event_success(event, handler_name, result)
    end
    
    it 'truncates long string results' do
      long_result = 'a' * 200
      expect(service.logger).to receive(:info)
      expect(service.logger).to receive(:debug).with("#{handler_name} result: #{long_result[0..100]}...")
      service.log_event_success(event, handler_name, long_result)
    end
  end
  
  describe '#log_event_failure' do
    let(:error) { StandardError.new('Test error') }
    
    before do
      error.set_backtrace(['line1', 'line2'])
    end
    
    it 'logs failed event handling with error details' do
      expect(service.logger).to receive(:error).with("#{handler_name} failed to process event: #{event.event_type} [#{event.id}]")
      expect(service.logger).to receive(:error).with("Error: Test error")
      expect(service.logger).to receive(:error).with("line1\nline2")
      service.log_event_failure(event, handler_name, error)
    end
  end
  
  describe '#process_event' do
    it 'processes event successfully' do
      result = { processed: true }
      
      expect(service).to receive(:log_event_processing)
      expect(service).to receive(:log_event_success)
      expect(service).to receive(:record_event_metrics)
      
      processed_result = service.process_event(event, handler_name) { result }
      expect(processed_result).to eq(result)
    end
    
    it 'handles errors during processing' do
      error = StandardError.new('Test error')
      
      expect(service).to receive(:log_event_processing)
      expect(service).to receive(:log_event_failure)
      expect(service).to receive(:record_event_metrics)
      
      expect {
        service.process_event(event, handler_name) { raise error }
      }.to raise_error(StandardError, 'Test error')
    end
  end
  
  describe '#validate_event_data' do
    it 'validates event data with all required fields' do
      event.data = { 'field1' => 'value1', 'field2' => 'value2' }
      expect(service.validate_event_data(event, ['field1', 'field2'])).to be true
    end
    
    it 'validates event data with symbol keys' do
      event.data = { field1: 'value1', field2: 'value2' }
      expect(service.validate_event_data(event, ['field1', 'field2'])).to be true
    end
    
    it 'raises error for missing required fields' do
      event.data = { 'field1' => 'value1' }
      expect {
        service.validate_event_data(event, ['field1', 'field2'])
      }.to raise_error(ArgumentError, /missing required fields/)
    end
  end
end
