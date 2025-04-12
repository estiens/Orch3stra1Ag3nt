# BaseAgent: Inherit from this for per-agent queue and model config

class BaseAgent < Regent::Agent
  def initialize(purpose, **kwargs)
    # Always pass a model kwarg: user-supplied or default_model
    super(purpose, model: kwargs.fetch(:model, self.class.default_model))
  end

  def self.queue_name
    name.demodulize.underscore.to_sym
  end

  def self.default_model
    "deepseek/deepseek-chat-v3-0324"
  end
end
