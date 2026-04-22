defmodule Trivium.Build.Agents.PlannerTest do
  use ExUnit.Case, async: false

  alias Trivium.Build.Agents.Planner
  alias Trivium.Build.Types.{Plan, Step}
  alias Trivium.LLM.Mock

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  describe "run/2" do
    test "turns a spec + base_ref into a %Plan{} with parsed ordered steps" do
      canned = """
      Aqui está o plano:

      ```json
      {"topic": "Add cache to fetcher", "steps": [
        {"title": "Add ETS table", "files": ["lib/cache.ex"], "acceptance": "Cache.start_link/0 returns {:ok, pid}"},
        {"title": "Wire fetcher to cache", "files": ["lib/fetcher.ex"], "acceptance": "Fetcher.fetch/1 hits cache on second call"}
      ]}
      ```
      """

      Mock.set_script(:planner, [canned])

      assert {:ok, %Plan{} = plan} =
               Planner.run("spec text", base_ref: "deadbeef", llm_client: Mock)

      assert plan.topic == "Add cache to fetcher"
      assert plan.base_ref == "deadbeef"
      assert plan.status == :draft
      assert length(plan.steps) == 2

      [first, second] = plan.steps
      assert %Step{index: 1, title: "Add ETS table", files: ["lib/cache.ex"]} = first
      assert first.acceptance =~ "Cache.start_link/0"
      assert %Step{index: 2, title: "Wire fetcher to cache"} = second
    end

    test "returns {:error, _} when the LLM output has no JSON block" do
      Mock.set_script(:planner, ["sem json aqui, só texto livre"])

      assert {:error, _} =
               Planner.run("spec text", base_ref: "deadbeef", llm_client: Mock)
    end
  end
end
