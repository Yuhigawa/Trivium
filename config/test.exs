import Config

config :trivium,
  llm_client: Trivium.LLM.Mock,
  max_attempts: 2
