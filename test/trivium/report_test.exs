defmodule Trivium.ReportTest do
  use ExUnit.Case, async: true

  alias Trivium.Report
  alias Trivium.Types.{Attempt, Idea, Result, Review}

  defp review(role, score), do: %Review{role: role, score: score, justification: "j"}

  test "approved single attempt" do
    attempt = %Attempt{
      n: 1,
      idea: %Idea{content: "problema X solução Y"},
      reviews: [review(:idea_writer, 9), review(:technical_researcher, 8), review(:qa, 9)]
    }

    result = %Result{
      status: :approved,
      attempts: [attempt],
      final_idea: attempt.idea,
      final_reviews: attempt.reviews
    }

    report = Report.format(result)
    assert report =~ "APPROVED"
    assert report =~ "9/10"
    refute report =~ "Attempt history"
  end

  test "rejected com múltiplas tentativas mostra histórico" do
    attempts =
      [1, 2, 3]
      |> Enum.map(fn n ->
        %Attempt{
          n: n,
          idea: %Idea{content: "v#{n}"},
          reviews: [review(:idea_writer, 5), review(:technical_researcher, 5), review(:qa, 5)]
        }
      end)

    result = %Result{
      status: :rejected,
      attempts: attempts,
      final_idea: List.last(attempts).idea,
      final_reviews: List.last(attempts).reviews
    }

    report = Report.format(result)
    assert report =~ "REJECTED"
    assert report =~ "Attempt history"
    assert report =~ "attempt 3"
  end
end
