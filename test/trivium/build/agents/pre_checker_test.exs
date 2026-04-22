defmodule Trivium.Build.Agents.PreCheckerTest do
  use ExUnit.Case, async: false

  alias Trivium.Build.Agents.PreChecker
  alias Trivium.Build.Types.{Plan, Step, PreCheck}
  alias Trivium.LLM.Mock
  alias Trivium.Types.ProjectContext

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
      status: :draft,
      created_at: DateTime.utc_now(),
      steps: [
        %Step{index: 1, title: "Touch foo", files: ["lib/foo.ex"], acceptance: "compiles"}
      ]
    }
  end

  defp sample_ctx do
    %ProjectContext{path: System.tmp_dir!(), type: :feature, task: "x"}
  end

  test "ok verdict surfaces empty notes" do
    Mock.set_script(:pre_checker, [
      "```json\n{\"verdict\": \"ok\", \"notes\": [], \"suggested_changes\": []}\n```"
    ])

    assert {:ok, %PreCheck{verdict: :ok, notes: [], suggested_changes: []}} =
             PreChecker.run(sample_plan(), project_context: sample_ctx(), llm_client: Mock)
  end

  test "revise verdict surfaces notes and suggestions" do
    Mock.set_script(:pre_checker, [
      "```json\n{\"verdict\": \"revise\", \"notes\": [\"lib/foo.ex já é grande demais\"], \"suggested_changes\": [\"Split foo.ex first\"]}\n```"
    ])

    assert {:ok,
            %PreCheck{
              verdict: :revise,
              notes: ["lib/foo.ex já é grande demais"],
              suggested_changes: ["Split foo.ex first"]
            }} =
             PreChecker.run(sample_plan(), project_context: sample_ctx(), llm_client: Mock)
  end
end
