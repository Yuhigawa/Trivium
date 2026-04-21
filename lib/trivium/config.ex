defmodule Trivium.Config do
  @moduledoc """
  Acesso centralizado às configurações da app. Flags da CLI sobrescrevem defaults.
  """

  def get(key, default \\ nil) do
    Application.get_env(:trivium, key, default)
  end

  def model_for(role) when role in [:idea_writer, :technical_researcher, :qa] do
    models = get(:models, %{})
    Map.fetch!(models, role)
  end

  def api_key do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil -> get(:api_key)
      "" -> get(:api_key)
      value -> value
    end
  end

  def max_attempts, do: get(:max_attempts, 3)
  def approval_threshold, do: get(:approval_threshold, 7)
  def llm_client, do: get(:llm_client, Trivium.LLM.Anthropic)
  def api_base_url, do: get(:api_base_url, "https://api.anthropic.com/v1/messages")
  def anthropic_version, do: get(:anthropic_version, "2023-06-01")

  def put(key, value), do: Application.put_env(:trivium, key, value)
end
