defmodule Trivium.Build.Agents.Reviewer do
  @moduledoc """
  Validates a code diff against the plan that produced it.
  """

  alias Trivium.Config
  alias Trivium.Build.Types.{Plan, Review}

  @system_prompt """
  Você é um code reviewer. Recebe (1) um plano com steps + critérios de aceite
  e (2) um diff git. Sua função:

  - Verificar se o diff entrega o que cada step prometeu (acceptance bate?).
  - Verificar se regras de negócio existentes foram preservadas.
  - Sugerir melhorias específicas (não genéricas como "adicione testes").

  Verdicts:
  - "approved" se o diff entrega o plano sem regredir nada.
  - "needs_work" se faltou algo, escopo diverge, ou há regressão.

  Formato OBRIGATÓRIO no fim — JSON puro:

  ```json
  {"verdict": "approved|needs_work", "findings": ["..."], "improvements": ["..."]}
  ```
  """

  def run(%Plan{} = plan, diff, opts) when is_binary(diff) do
    client = Keyword.get(opts, :llm_client) || Config.llm_client()

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: render(plan, diff)}
    ]

    model = Config.model_for(:qa)
    llm_opts = [role: :reviewer]

    with {:ok, text} <- client.complete(model, messages, llm_opts),
         {:ok, json} <- find_json(text),
         {:ok, %{"verdict" => v} = parsed} <- Jason.decode(json),
         {:ok, verdict} <- parse_verdict(v) do
      {:ok,
       %Review{
         verdict: verdict,
         findings: parsed["findings"] || [],
         improvements: parsed["improvements"] || []
       }}
    else
      {:error, _} = e -> e
      :error -> {:error, :no_json_in_reviewer_output}
      {:ok, other} -> {:error, {:review_missing_fields, other}}
      err -> {:error, err}
    end
  end

  defp render(%Plan{} = p, diff) do
    steps =
      p.steps
      |> Enum.map_join("\n", fn s ->
        "#{s.index}. #{s.title} — accept: #{s.acceptance} — done?: #{s.done?}"
      end)

    """
    Plano:

    Tópico: #{p.topic}

    Steps:
    #{steps}

    Diff a revisar:

    ```diff
    #{diff}
    ```
    """
  end

  defp find_json(text) do
    case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
      [_, json] -> {:ok, json}
      _ -> :error
    end
  end

  defp parse_verdict("approved"), do: {:ok, :approved}
  defp parse_verdict("needs_work"), do: {:ok, :needs_work}
  defp parse_verdict(other), do: {:error, {:invalid_verdict, other}}
end
