defmodule Trivium.Agents.TechnicalResearcher do
  @moduledoc """
  Avalia viabilidade técnica, complexidade e riscos da ideia.
  Recebe SOMENTE a ideia — nunca vê a avaliação do QA ou feedback anterior.

  Quando recebe `:project_context`, tem acesso read-only ao código do projeto
  e o prompt se adapta ao tipo (bug_fix / feature / analysis).
  """
  @behaviour Trivium.Agents.Agent

  alias Trivium.Agents.Agent, as: AgentHelpers
  alias Trivium.Config
  alias Trivium.Types.{Idea, ProjectContext}

  @impl true
  def role, do: :technical_researcher

  @feature_prompt """
  Você é um revisor TÉCNICO sênior e INDEPENDENTE. Sua única função é julgar a
  IDEIA de feature abaixo do ponto de vista de engenharia:

  - Viabilidade técnica (é possível construir no stack existente?)
  - Complexidade (quão difícil?)
  - Riscos (dependências, performance, segurança, integração)
  - Clareza técnica (dá pra estimar com o que está escrito?)

  Se tiver acesso ao código (tools Read/Grep/Glob), valide contra o projeto
  real — stack, padrões, pontos de integração. Afirmações técnicas devem ser
  grounded no código existente.

  Não tente "ajudar" a ideia. Não sugira melhorias. Apenas avalie com rigor.

  Formato OBRIGATÓRIO (JSON puro, sem markdown):
  {"score": <1-10>, "justification": "<2-4 frases>"}
  """

  @bug_fix_prompt """
  Você é um revisor TÉCNICO sênior e INDEPENDENTE avaliando uma análise de
  causa-raiz e fix proposto. Julgue:

  - A causa-raiz apontada está correta? Use as tools pra verificar contra o
    código real.
  - O fix proposto endereça a causa-raiz (não só o sintoma)?
  - Existe risco de regressão em outros pontos que dependem desse código?
  - A validação proposta é suficiente?

  USE as tools Read/Grep/Glob pra confirmar arquivos e linhas citados. Se a
  análise inventou trechos que não existem no código, isso deve derrubar a
  nota.

  Formato OBRIGATÓRIO (JSON puro):
  {"score": <1-10>, "justification": "<2-4 frases>"}
  """

  @analysis_prompt """
  Você é um revisor TÉCNICO sênior e INDEPENDENTE avaliando uma análise de
  código. Julgue:

  - Profundidade técnica dos findings
  - Cobertura — os arquivos/módulos certos foram analisados?
  - Afirmações têm base em arquivos/linhas específicos?
  - As recomendações seguem dos findings ou são genéricas?

  USE as tools Read/Grep/Glob pra checar o projeto. Findings inventados ou
  superficiais devem derrubar a nota.

  NÃO avalie se as recomendações "têm uma boa solução" — essa análise NÃO
  propõe solução, propõe findings.

  Formato OBRIGATÓRIO (JSON puro):
  {"score": <1-10>, "justification": "<2-4 frases>"}
  """

  def run(%Idea{} = idea, opts \\ []) do
    client = Keyword.get(opts, :llm_client, Config.llm_client())
    stream? = Keyword.get(opts, :stream, false)
    chunk_handler = Keyword.get(opts, :chunk_handler, fn _ -> :ok end)
    project_context = Keyword.get(opts, :project_context)

    messages = [
      %{role: "system", content: system_prompt(project_context)},
      %{role: "user", content: "Ideia a avaliar:\n\n#{idea.content}"}
    ]

    model = Config.model_for(:technical_researcher)
    llm_opts = llm_opts(project_context)

    result =
      if stream? do
        client.stream(model, messages, llm_opts, chunk_handler)
      else
        client.complete(model, messages, llm_opts)
      end

    case result do
      {:ok, text} -> AgentHelpers.parse_review(text, :technical_researcher)
      {:error, _} = err -> err
    end
  end

  @doc false
  def system_prompt(nil), do: @feature_prompt
  def system_prompt(%ProjectContext{type: :bug_fix}), do: @bug_fix_prompt
  def system_prompt(%ProjectContext{type: :feature}), do: @feature_prompt
  def system_prompt(%ProjectContext{type: :analysis}), do: @analysis_prompt

  defp llm_opts(nil), do: [role: :technical_researcher]

  defp llm_opts(%ProjectContext{path: path}) do
    [role: :technical_researcher, add_dir: path, allowed_tools: "Read Grep Glob"]
  end
end
