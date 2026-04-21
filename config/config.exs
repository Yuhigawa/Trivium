import Config

config :trivium,
  max_attempts: 3,
  approval_threshold: 7,
  models: %{
    idea_writer: "claude-opus-4-7",
    technical_researcher: "claude-sonnet-4-6",
    qa: "claude-haiku-4-5-20251001"
  },
  llm_client: Trivium.LLM.ClaudeCLI,
  api_base_url: "https://api.anthropic.com/v1/messages",
  anthropic_version: "2023-06-01"

if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
