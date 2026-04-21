defmodule Trivium.Agents.TechnicalResearcher do
  @moduledoc """
  Avalia viabilidade técnica, complexidade e riscos da ideia.
  Recebe SOMENTE a ideia — nunca vê a avaliação do QA ou feedback anterior.
  """
  @behaviour Trivium.Agents.Agent

  alias Trivium.Agents.Agent, as: AgentHelpers
  alias Trivium.Config
  alias Trivium.Types.Idea

  @impl true
  def role, do: :technical_researcher

  @system_prompt """
  Você é um revisor TÉCNICO sênior e INDEPENDENTE. Sua única função é julgar a
  ideia abaixo do ponto de vista de engenharia:

  - Viabilidade técnica (é possível construir?)
  - Complexidade (quão difícil?)
  - Riscos (pontos cegos, dependências externas, performance, segurança)
  - Clareza técnica (a ideia dá informação suficiente para estimar?)

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

    model = Config.model_for(:technical_researcher)

    result =
      if stream? do
        client.stream(model, messages, [role: :technical_researcher], chunk_handler)
      else
        client.complete(model, messages, role: :technical_researcher)
      end

    case result do
      {:ok, text} -> AgentHelpers.parse_review(text, :technical_researcher)
      {:error, _} = err -> err
    end
  end
end
