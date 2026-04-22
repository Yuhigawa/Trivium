defmodule Trivium.Build.Agents.PreChecker do
  @moduledoc """
  Reads existing code mentioned in the plan and validates the plan against it.
  Output verdict :ok or :revise, with notes and suggested plan edits.
  """

  alias Trivium.Config
  alias Trivium.Build.Types.{Plan, PreCheck}

  @system_prompt """
  Você é um revisor pré-implementação. Receba (1) um plano de steps e (2)
  acesso read-only ao código do projeto via Read/Grep/Glob. Sua função:

  - Ler os arquivos que o plano vai tocar.
  - Detectar conflitos: mudanças que quebram código existente, padrões
    ignorados, redundância (algo similar já existe).
  - Sugerir edits ao plano (não reescreva o plano — só sugira).

  Verdicts:
  - "ok" se o plano está alinhado com o código existente e é seguro executar.
  - "revise" se há conflitos ou sugestões importantes.

  Formato OBRIGATÓRIO no fim — JSON puro:

  ```json
  {"verdict": "ok|revise", "notes": ["..."], "suggested_changes": ["..."]}
  ```
  """

  def run(%Plan{} = plan, opts) do
    client = Keyword.get(opts, :llm_client, Config.llm_client())
    project_context = Keyword.fetch!(opts, :project_context)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: render_plan_for_review(plan)}
    ]

    model = Config.model_for(:technical_researcher)

    llm_opts = [
      role: :pre_checker,
      add_dir: project_context.path,
      allowed_tools: "Read Grep Glob"
    ]

    with {:ok, text} <- client.complete(model, messages, llm_opts),
         {:ok, json} <- find_json(text),
         {:ok, %{"verdict" => v} = parsed} <- Jason.decode(json),
         {:ok, verdict} <- parse_verdict(v) do
      {:ok,
       %PreCheck{
         verdict: verdict,
         notes: parsed["notes"] || [],
         suggested_changes: parsed["suggested_changes"] || []
       }}
    else
      {:error, _} = e -> e
      :error -> {:error, :no_json_in_pre_checker_output}
      {:ok, other} -> {:error, {:pre_check_missing_fields, other}}
      err -> {:error, err}
    end
  end

  defp render_plan_for_review(%Plan{} = p) do
    steps =
      p.steps
      |> Enum.map_join("\n", fn s ->
        "#{s.index}. #{s.title}\n   files: #{Enum.join(s.files, ", ")}\n   accept: #{s.acceptance}"
      end)

    """
    Plano a revisar:

    Tópico: #{p.topic}

    Steps:
    #{steps}
    """
  end

  defp find_json(text) do
    case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
      [_, json] -> {:ok, json}
      _ -> :error
    end
  end

  defp parse_verdict("ok"), do: {:ok, :ok}
  defp parse_verdict("revise"), do: {:ok, :revise}
  defp parse_verdict(other), do: {:error, {:invalid_verdict, other}}
end
