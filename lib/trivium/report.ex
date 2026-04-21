defmodule Trivium.Report do
  @moduledoc "Formata o resultado final em markdown legível para humano."

  alias Trivium.Types.{Attempt, ProjectContext, Result, Review}

  def format(%Result{} = result) do
    [
      project_block(result),
      header(result),
      final_block(result),
      scores_block(result),
      history_block(result)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp project_block(%Result{project_context: nil}), do: ""

  defp project_block(%Result{project_context: %ProjectContext{} = ctx}) do
    """
    Project: #{ctx.path}
    Type:    #{ctx.type}
    Task:    #{ctx.task}
    """
    |> String.trim_trailing()
  end

  defp header(%Result{status: :approved, attempts: attempts}) do
    n = length(attempts)
    "───── FINAL REPORT ─────\nStatus: ✅ APPROVED after #{n} attempt#{if n > 1, do: "s", else: ""}"
  end

  defp header(%Result{status: :rejected, attempts: attempts}) do
    n = length(attempts)
    "───── FINAL REPORT ─────\nStatus: ❌ REJECTED after #{n} attempt#{if n > 1, do: "s", else: ""}"
  end

  defp header(%Result{status: :error}) do
    "───── FINAL REPORT ─────\nStatus: ⚠ ERROR during evaluation"
  end

  defp final_block(%Result{final_idea: nil}), do: ""

  defp final_block(%Result{final_idea: idea}) do
    "## Final idea\n\n#{idea.content}"
  end

  defp scores_block(%Result{final_reviews: nil}), do: ""

  defp scores_block(%Result{final_reviews: reviews}) do
    lines =
      reviews
      |> Enum.sort_by(& &1.role)
      |> Enum.map_join("\n", fn %Review{role: r, score: s, justification: j} ->
        "- #{pad_role(r)} #{s}/10 — #{j}"
      end)

    "## Scores\n\n" <> lines
  end

  defp history_block(%Result{attempts: attempts}) when length(attempts) <= 1, do: ""

  defp history_block(%Result{attempts: attempts}) do
    body =
      attempts
      |> Enum.map(fn %Attempt{n: n, reviews: reviews} ->
        line =
          reviews
          |> Enum.sort_by(& &1.role)
          |> Enum.map_join(", ", fn r -> "#{pad_role(r.role)} #{r.score}" end)

        "- attempt #{n}: #{line}"
      end)
      |> Enum.join("\n")

    "## Attempt history\n\n" <> body
  end

  defp pad_role(:idea_writer), do: "idea-writer:"
  defp pad_role(:technical_researcher), do: "tech-research:"
  defp pad_role(:qa), do: "qa:            "
  defp pad_role(other), do: "#{other}:"
end
