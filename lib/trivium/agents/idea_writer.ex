defmodule Trivium.Agents.IdeaWriter do
  @moduledoc """
  Gera ou refina a ideia. Recebe a task original e, opcionalmente, o histórico
  de tentativas anteriores com justificativas dos revisores que REPROVARAM —
  nunca vê as opiniões dos que aprovaram (isolamento da narrativa).
  """
  @behaviour Trivium.Agents.Agent

  alias Trivium.Agents.Agent, as: AgentHelpers
  alias Trivium.Config
  alias Trivium.Types.{Attempt, Idea}

  @impl true
  def role, do: :idea_writer

  @review_system_prompt """
  Você é o idea-writer avaliando SUA PRÓPRIA ideia, já finalizada. Você NÃO sabe
  mais nada além do texto da ideia abaixo — avalie do ponto de vista de um autor
  crítico relendo o próprio trabalho.

  Julgue:
  - A ideia está clara, coerente e completa?
  - O problema está bem definido e o valor está explícito?
  - As seções (Problema, Solução, Escopo, Fora de escopo, Critérios) foram de
    fato preenchidas com substância, não com vagueza?

  Dê uma nota 1-10 honesta. Se ficou confuso ou vago, diga.

  Formato OBRIGATÓRIO (JSON puro):
  {"score": <1-10>, "justification": "<2-4 frases>"}
  """

  @system_prompt """
  Você é um idea-writer sênior. Sua tarefa é transformar um pedido do usuário em
  uma IDEIA clara e estruturada para desenvolvimento.

  Responda em markdown, com estas seções obrigatórias:

  ## Problema
  Qual problema real isso resolve? Para quem?

  ## Solução
  Descrição concisa da solução proposta.

  ## Escopo
  O que está incluído (lista objetiva).

  ## Fora de escopo
  O que deliberadamente NÃO será feito (YAGNI).

  ## Critérios de sucesso
  Como saberemos que deu certo (mensurável se possível).

  Quando receber FEEDBACK de tentativas anteriores, trate cada crítica com rigor:
  reescreva a ideia endereçando as objeções. Não se defenda — reformule.
  """

  def run(task, previous_attempts \\ [], opts \\ []) do
    client = Keyword.get(opts, :llm_client, Config.llm_client())
    stream? = Keyword.get(opts, :stream, false)
    chunk_handler = Keyword.get(opts, :chunk_handler, fn _ -> :ok end)

    messages = build_messages(task, previous_attempts)
    model = Config.model_for(:idea_writer)

    result =
      if stream? do
        client.stream(model, messages, [role: :idea_writer], chunk_handler)
      else
        client.complete(model, messages, role: :idea_writer)
      end

    case result do
      {:ok, text} -> {:ok, %Idea{content: String.trim(text)}}
      {:error, _} = err -> err
    end
  end

  @doc """
  Self-review: segunda chamada LLM, fresca, que só recebe a ideia final e
  devolve um Review. Preserva isolamento — não "lembra" de ter gerado a ideia.
  """
  def self_review(%Idea{} = idea, opts \\ []) do
    client = Keyword.get(opts, :llm_client, Config.llm_client())
    stream? = Keyword.get(opts, :stream, false)
    chunk_handler = Keyword.get(opts, :chunk_handler, fn _ -> :ok end)

    messages = [
      %{role: "system", content: @review_system_prompt},
      %{role: "user", content: "Ideia a avaliar:\n\n#{idea.content}"}
    ]

    model = Config.model_for(:idea_writer)

    result =
      if stream? do
        client.stream(model, messages, [role: :idea_writer_review], chunk_handler)
      else
        client.complete(model, messages, role: :idea_writer_review)
      end

    case result do
      {:ok, text} -> AgentHelpers.parse_review(text, :idea_writer)
      {:error, _} = err -> err
    end
  end

  defp build_messages(task, []) do
    [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: "Tarefa:\n\n#{task}\n\nGere a ideia inicial."}
    ]
  end

  defp build_messages(task, previous_attempts) do
    feedback = format_feedback(previous_attempts)

    [
      %{role: "system", content: @system_prompt},
      %{
        role: "user",
        content: """
        Tarefa original:

        #{task}

        Tentativas anteriores e feedback de quem REPROVOU (score ≤ 7):

        #{feedback}

        Reescreva a ideia endereçando essas objeções.
        """
      }
    ]
  end

  defp format_feedback(attempts) do
    attempts
    |> Enum.map(fn %Attempt{n: n, idea: idea, reviews: reviews} ->
      failed =
        reviews
        |> Enum.filter(&(&1.score <= Trivium.Config.approval_threshold()))

      review_block =
        failed
        |> Enum.map_join("\n", fn r ->
          "- [#{r.role}] score #{r.score}: #{r.justification}"
        end)

      """
      ### Tentativa #{n}
      Ideia:
      #{idea.content}

      Feedback dos que reprovaram:
      #{review_block}
      """
    end)
    |> Enum.join("\n---\n")
  end
end
