defmodule Trivium.Build.Agents.ReviewerTest do
  use ExUnit.Case, async: false

  alias Trivium.Build.Agents.Reviewer
  alias Trivium.Build.Types.{Plan, Step, Review}
  alias Trivium.LLM.Mock

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  defp sample_plan do
    %Plan{
      topic: "Add X",
      base_ref: "abc",
      status: :review_pending,
      created_at: DateTime.utc_now(),
      steps: [
        %Step{
          index: 1,
          title: "Touch foo",
          files: ["lib/foo.ex"],
          acceptance: "compiles",
          done?: true
        }
      ]
    }
  end

  defp sample_diff do
    """
    diff --git a/lib/foo.ex b/lib/foo.ex
    +defmodule Foo do
    +  def bar, do: :ok
    +end
    """
  end

  describe "run/3" do
    test "approved verdict" do
      Mock.set_script(:reviewer, [
        "```json\n{\"verdict\": \"approved\", \"findings\": [], \"improvements\": []}\n```"
      ])

      assert {:ok, %Review{verdict: :approved, findings: [], improvements: []}} =
               Reviewer.run(sample_plan(), sample_diff(), llm_client: Mock)
    end

    test "needs_work verdict surfaces findings" do
      Mock.set_script(:reviewer, [
        "```json\n{\"verdict\": \"needs_work\", \"findings\": [\"foo.bar/0 has no doc\"], \"improvements\": [\"add @doc\"]}\n```"
      ])

      assert {:ok,
              %Review{
                verdict: :needs_work,
                findings: ["foo.bar/0 has no doc"],
                improvements: ["add @doc"]
              }} = Reviewer.run(sample_plan(), sample_diff(), llm_client: Mock)
    end
  end
end
