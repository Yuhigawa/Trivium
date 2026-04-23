defmodule Trivium.Build.Agents.Planner do
  @moduledoc """
  Turns an approved spec into a structured `%Plan{}` of ordered steps.

  Output JSON contract:

      {"topic": "...", "steps": [{"title", "files", "acceptance", "notes"?}]}
  """

  alias Trivium.Config
  alias Trivium.Build.Types.{Plan, Step}
  alias Trivium.Types.ProjectContext

  @system_prompt """
  Você é um planner sênior. Receba uma especificação aprovada e produza um
  plano de implementação com passos ORDENADOS e ATÔMICOS (cada passo é um
  commit). Para cada passo dê:

  - title: descrição curta (≤ 80 chars)
  - files: lista de arquivos a criar/editar (paths exatos quando souber)
  - acceptance: critério verificável (teste passando, mix compile, etc.)
  - notes (opcional): contexto extra pro implementador

  Se tiver acesso ao código (Read/Grep/Glob), use-o para identificar arquivos
  e padrões existentes a respeitar.

  Formato OBRIGATÓRIO no fim da resposta — JSON em bloco markdown:

  ```json
  {"topic": "<short topic>", "steps": [{"title": "...", "files": ["..."], "acceptance": "..."}]}
  ```
  """

  def run(spec, opts) do
    base_ref = Keyword.fetch!(opts, :base_ref)
    client = Keyword.get(opts, :llm_client) || Config.llm_client()
    project_context = Keyword.get(opts, :project_context)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: "Especificação aprovada:\n\n#{spec}"}
    ]

    model = Config.model_for(:idea_writer)
    llm_opts = llm_opts(project_context)

    with {:ok, text} <- client.complete(model, messages, llm_opts),
         {:ok, json} <- find_json(text),
         {:ok, %{"topic" => topic, "steps" => raw_steps}} <- Jason.decode(json) do
      steps =
        raw_steps
        |> Enum.with_index(1)
        |> Enum.map(fn {s, i} ->
          %Step{
            index: i,
            title: s["title"] || "(untitled)",
            files: s["files"] || [],
            acceptance: s["acceptance"],
            notes: s["notes"]
          }
        end)

      {:ok,
       %Plan{
         topic: topic,
         base_ref: base_ref,
         steps: steps,
         status: :draft,
         created_at: DateTime.utc_now(),
         trivium_version: Application.spec(:trivium, :vsn) |> to_string()
       }}
    else
      {:error, _} = e -> e
      :error -> {:error, :no_json_in_planner_output}
      other -> {:error, {:planner_unexpected, other}}
    end
  end

  defp find_json(text) do
    case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
      [_, json] -> {:ok, json}
      _ -> :error
    end
  end

  defp llm_opts(nil), do: [role: :planner]

  defp llm_opts(%ProjectContext{path: path}),
    do: [role: :planner, add_dir: path, allowed_tools: "Read Grep Glob"]
end
