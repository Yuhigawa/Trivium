defmodule Trivium.Build.OrchestratorTest do
  use ExUnit.Case, async: false

  alias Trivium.Build.Orchestrator
  alias Trivium.Build.PlanIO
  alias Trivium.LLM.Mock
  alias Trivium.Types.ProjectContext

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  @planner_response """
  ```json
  {"topic": "Add X", "steps": [
    {"title": "Add module", "files": ["lib/x.ex"], "acceptance": "compiles"}
  ]}
  ```
  """

  @pre_check_response """
  ```json
  {"verdict": "ok", "notes": [], "suggested_changes": []}
  ```
  """

  test "build/2 writes a plan file and returns its path" do
    tmp = Path.join(System.tmp_dir!(), "trivium-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    # Initialise a git repo with one commit so rev-parse HEAD works.
    {_, 0} = System.cmd("git", ["init"], cd: tmp)
    {_, 0} = System.cmd("git", ["config", "user.email", "t@t"], cd: tmp)
    {_, 0} = System.cmd("git", ["config", "user.name", "t"], cd: tmp)
    File.write!(Path.join(tmp, "README.md"), "x")
    {_, 0} = System.cmd("git", ["add", "."], cd: tmp)
    {_, 0} = System.cmd("git", ["commit", "-m", "init"], cd: tmp)

    ctx = %ProjectContext{path: tmp, type: :feature, task: "Add X"}

    Mock.set_script(:planner, [@planner_response])
    Mock.set_script(:pre_checker, [@pre_check_response])

    {:ok, path} = Orchestrator.build("spec text here", project_context: ctx, llm_client: Mock)

    assert File.exists?(path)
    {:ok, plan} = path |> File.read!() |> PlanIO.decode()

    assert plan.topic == "Add X"
    assert plan.status == :draft
    assert byte_size(plan.base_ref) >= 7
    assert length(plan.steps) == 1

    File.rm_rf!(tmp)
  end
end
