defmodule Trivium.Agents.QA do
  @moduledoc """
  Avalia testabilidade, critérios de aceite claros e cobertura de edge cases.
  Recebe SOMENTE a ideia — nunca vê a avaliação técnica.

  Quando recebe `:project_context`, tem acesso read-only ao código do projeto
  e o prompt se adapta ao tipo (bug_fix / feature / analysis).
  """
  @behaviour Trivium.Agents.Agent

  alias Trivium.Agents.Agent, as: AgentHelpers
  alias Trivium.Config
  alias Trivium.Types.{Idea, ProjectContext}

  @impl true
  def role, do: :qa

  @feature_prompt """
  Você é um engenheiro de QA sênior e INDEPENDENTE. Julgue a IDEIA de feature
  do ponto de vista de testabilidade:

  - Critérios de aceite claros e mensuráveis?
  - Dá pra escrever testes end-to-end a partir da ideia?
  - Edge cases e cenários de falha considerados?
  - Escopo/Fora-de-escopo definidos o suficiente pra evitar ambiguidade?

  Se tiver acesso ao código (tools Read/Grep/Glob), verifique se a ideia
  considera os pontos de teste/qualidade já existentes no projeto.

  Não tente "ajudar" a ideia. Apenas avalie com rigor.

  Formato OBRIGATÓRIO (JSON puro):
  {"score": <1-10>, "justification": "<2-4 frases>"}
  """

  @bug_fix_prompt """
  Você é um engenheiro de QA sênior e INDEPENDENTE avaliando um fix de bug.
  Julgue:

  - A validação proposta é robusta? Cobre o caso original do bug?
  - Os critérios de sucesso são verificáveis por teste (manual ou
    automatizado)?
  - Regressão: pontos colaterais foram considerados?
  - É possível escrever um teste que CAIA sem o fix e PASSE com ele?

  ### Checklist — antes de dar score alto (>= 7), todos devem ser SIM
  1. Existe um comando de teste CONCRETO e específico pra validar (não apenas
     "testar manualmente")?
  2. Esse teste claramente falharia sem o fix e passaria com ele?
  3. O output esperado do teste está DEFINIDO (não só "funciona" ou "ok")?

  Se qualquer resposta for "não" ou "não dá pra ter certeza", a nota deve
  refletir isso.

  USE as tools Read/Grep/Glob pra ver se já existem testes próximos ao
  arquivo afetado e pra conferir referências do código.

  Formato OBRIGATÓRIO (JSON puro):
  {"score": <1-10>, "justification": "<2-4 frases>"}
  """

  @analysis_prompt """
  Você é um engenheiro de QA sênior e INDEPENDENTE avaliando uma análise de
  código. Julgue sob a ótica de ACIONABILIDADE:

  - Os findings são específicos o bastante pra alguém trabalhar com eles?
  - Há ambiguidades que deixariam um implementador parado?
  - Os "próximos passos" são concretos ou vagos?
  - Existe algum gap óbvio (áreas não cobertas que deveriam estar)?

  USE as tools Read/Grep/Glob para verificar o escopo coberto.

  NÃO avalie implementação — a análise não propõe uma. Avalie se ela serve
  como insumo pra planejar o próximo passo.

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

    model = Config.model_for(:qa)
    llm_opts = llm_opts(project_context)

    result =
      if stream? do
        client.stream(model, messages, llm_opts, chunk_handler)
      else
        client.complete(model, messages, llm_opts)
      end

    case result do
      {:ok, text} -> AgentHelpers.parse_review(text, :qa)
      {:error, _} = err -> err
    end
  end

  @doc false
  def system_prompt(nil), do: @feature_prompt
  def system_prompt(%ProjectContext{type: :bug_fix}), do: @bug_fix_prompt
  def system_prompt(%ProjectContext{type: :feature}), do: @feature_prompt
  def system_prompt(%ProjectContext{type: :analysis}), do: @analysis_prompt

  defp llm_opts(nil), do: [role: :qa]

  defp llm_opts(%ProjectContext{path: path}) do
    [role: :qa, add_dir: path, allowed_tools: "Read Grep Glob"]
  end
end
