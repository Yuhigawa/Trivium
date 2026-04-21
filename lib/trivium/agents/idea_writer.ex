defmodule Trivium.Agents.IdeaWriter do
  @moduledoc """
  Gera ou refina a ideia. Recebe a task original e, opcionalmente, o histórico
  de tentativas anteriores com justificativas dos revisores que REPROVARAM —
  nunca vê as opiniões dos que aprovaram (isolamento da narrativa).

  Quando recebe `:project_context`, o prompt ramifica por tipo (bug_fix /
  feature / analysis) e o agente recebe acesso read-only ao diretório do
  projeto via tools Read/Grep/Glob do Claude Code CLI.
  """
  @behaviour Trivium.Agents.Agent

  alias Trivium.Agents.Agent, as: AgentHelpers
  alias Trivium.Config
  alias Trivium.Types.{Attempt, Idea, ProjectContext}

  @impl true
  def role, do: :idea_writer

  @review_system_prompt """
  Você é o idea-writer avaliando SUA PRÓPRIA ideia, já finalizada. Você NÃO sabe
  mais nada além do texto da ideia abaixo — avalie do ponto de vista de um autor
  crítico relendo o próprio trabalho.

  Julgue:
  - A ideia está clara, coerente e completa?
  - O problema está bem definido e o valor está explícito?
  - Todas as seções foram preenchidas com substância, não com vagueza?

  Dê uma nota 1-10 honesta. Se ficou confuso ou vago, diga.

  Formato OBRIGATÓRIO (JSON puro):
  {"score": <1-10>, "justification": "<2-4 frases>"}
  """

  @feature_prompt """
  Você é um idea-writer sênior. Transforme o pedido do usuário em uma IDEIA de
  feature clara e estruturada em markdown, com estas seções obrigatórias:

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

  Se tiver acesso ao código do projeto (tools Read/Grep/Glob), explore-o para
  entender padrões existentes, stack e pontos de integração. A solução deve
  respeitar o estilo do projeto.

  Quando receber FEEDBACK de tentativas anteriores, trate cada crítica com rigor:
  reescreva endereçando as objeções. Não se defenda — reformule.
  """

  @bug_fix_prompt """
  Você é um root-cause analyst sênior. Diagnostique o bug descrito e proponha um
  fix, em markdown, com estas seções obrigatórias:

  ## Hipótese
  Hipóteses iniciais do que pode estar causando o problema (antes de investigar
  o código).

  ## Causa-raiz
  Após ler o código (use as tools), identifique a causa-raiz EXATA com
  referência a arquivos e linhas. Se não for possível determinar com confiança,
  diga "não foi possível isolar com certeza" e explique porquê.

  ## Fix proposto
  Mudança específica — arquivos, funções, comportamento. Seja concreto.

  ## Validação
  Como confirmar que o fix resolve sem introduzir regressão.

  ## Critérios de sucesso
  Condições objetivas que provam que o bug foi resolvido.

  USE as tools Read/Grep/Glob para investigar o código de verdade. Não invente
  arquivos/funções — se não achou, diga que não achou.

  Quando receber FEEDBACK de tentativas anteriores, reescreva endereçando as
  objeções. Não se defenda — reformule.
  """

  @analysis_prompt """
  Você é um code analyst sênior. Produza uma ANÁLISE do projeto ou área
  indicada, em markdown, com estas seções obrigatórias:

  ## Contexto
  Resumo do que foi analisado — arquivos, módulos, fluxos cobertos.

  ## Findings
  Observações concretas com referências a arquivos/linhas. Fatos, não opiniões.

  ## Recomendações
  Sugestões derivadas dos findings. Priorize por impacto.

  ## Riscos
  Pontos frágeis, dívida técnica, armadilhas pro próximo trabalho.

  ## Próximos passos
  O que um planner faria em seguida com esses findings.

  IMPORTANTE: você NÃO está propondo uma implementação. Não escreva "Solução"
  ou "Escopo de desenvolvimento". Seu papel é mapear, não construir.

  USE as tools Read/Grep/Glob para investigar o código. Afirmações sem base em
  arquivos específicos devem ser evitadas.

  Quando receber FEEDBACK de tentativas anteriores, reescreva endereçando as
  objeções. Não se defenda — reformule.
  """

  def run(task, previous_attempts \\ [], opts \\ []) do
    client = Keyword.get(opts, :llm_client, Config.llm_client())
    stream? = Keyword.get(opts, :stream, false)
    chunk_handler = Keyword.get(opts, :chunk_handler, fn _ -> :ok end)
    project_context = Keyword.get(opts, :project_context)

    messages = build_messages(task, previous_attempts, project_context)
    model = Config.model_for(:idea_writer)
    llm_opts = llm_opts(project_context, :idea_writer)

    result =
      if stream? do
        client.stream(model, messages, llm_opts, chunk_handler)
      else
        client.complete(model, messages, llm_opts)
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

  @doc false
  def system_prompt(nil), do: @feature_prompt
  def system_prompt(%ProjectContext{type: :bug_fix}), do: @bug_fix_prompt
  def system_prompt(%ProjectContext{type: :feature}), do: @feature_prompt
  def system_prompt(%ProjectContext{type: :analysis}), do: @analysis_prompt

  defp llm_opts(nil, role), do: [role: role]

  defp llm_opts(%ProjectContext{path: path}, role) do
    [role: role, add_dir: path, allowed_tools: "Read Grep Glob"]
  end

  defp build_messages(task, [], project_context) do
    [
      %{role: "system", content: system_prompt(project_context)},
      %{role: "user", content: user_message(task, project_context)}
    ]
  end

  defp build_messages(task, previous_attempts, project_context) do
    feedback = format_feedback(previous_attempts)

    [
      %{role: "system", content: system_prompt(project_context)},
      %{
        role: "user",
        content: """
        #{user_message(task, project_context)}

        Tentativas anteriores e feedback de quem REPROVOU (score ≤ 7):

        #{feedback}

        Reescreva endereçando essas objeções.
        """
      }
    ]
  end

  defp user_message(task, nil) do
    "Tarefa:\n\n#{task}\n\nGere a ideia inicial."
  end

  defp user_message(task, %ProjectContext{path: path, type: type}) do
    """
    Projeto: #{path}
    Tipo: #{type}

    Tarefa:

    #{task}
    """
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
