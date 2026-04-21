defmodule Trivium.LLM.Client do
  @moduledoc """
  Contrato para clientes LLM. A implementação padrão é `Trivium.LLM.Anthropic`.
  Testes injetam um mock via `config :trivium, :llm_client`.
  """

  @type role :: :idea_writer | :technical_researcher | :qa
  @type message :: %{role: String.t(), content: String.t()}
  @type options :: keyword()
  @type chunk_handler :: (String.t() -> any())

  @callback complete(model :: String.t(), messages :: [message()], options()) ::
              {:ok, String.t()} | {:error, term()}

  @callback stream(model :: String.t(), messages :: [message()], options(), chunk_handler()) ::
              {:ok, String.t()} | {:error, term()}
end
