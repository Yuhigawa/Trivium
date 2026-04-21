defmodule Trivium.Agents.QA do
  @moduledoc """
  Avalia testabilidade, critérios de aceite claros e cobertura de edge cases.
  Recebe SOMENTE a ideia — nunca vê a avaliação técnica.
  """
  @behaviour Trivium.Agents.Agent

  alias Trivium.Agents.Agent, as: AgentHelpers
  alias Trivium.Config
  alias Trivium.Types.Idea

  @impl true
  def role, do: :qa

  @system_prompt """
  Você é um engenheiro de QA sênior e INDEPENDENTE. Sua única função é julgar a
  ideia abaixo do ponto de vista de testabilidade:

  - Critérios de aceite estão claros e mensuráveis?
  - Dá para escrever testes end-to-end a partir dessa ideia?
  - Edge cases e cenários de falha foram considerados?
  - A ideia define escopo e fora-de-escopo o suficiente pra evitar ambiguidade?

  Não tente "ajudar" a ideia. Não sugira melhorias. Apenas avalie com rigor.
  Seu objetivo é dar uma NOTA honesta de 1 a 10.

  Formato de resposta OBRIGATÓRIO (JSON puro, sem markdown):
  {"score": <1-10>, "justification": "<2-4 frases explicando>"}
  """

  def run(%Idea{} = idea, opts \\ []) do
    client = Keyword.get(opts, :llm_client, Config.llm_client())
    stream? = Keyword.get(opts, :stream, false)
    chunk_handler = Keyword.get(opts, :chunk_handler, fn _ -> :ok end)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: "Ideia a avaliar:\n\n#{idea.content}"}
    ]

    model = Config.model_for(:qa)

    result =
      if stream? do
        client.stream(model, messages, [role: :qa], chunk_handler)
      else
        client.complete(model, messages, role: :qa)
      end

    case result do
      {:ok, text} -> AgentHelpers.parse_review(text, :qa)
      {:error, _} = err -> err
    end
  end
end
