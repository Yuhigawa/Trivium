defmodule Trivium.Build.Orchestrator do
  @moduledoc """
  Sequential pipeline: Planner -> PreChecker -> write plan file.
  """

  alias Trivium.Build.{PlanIO, Types}
  alias Trivium.Build.Agents.{Planner, PreChecker}
  alias Trivium.Build.Types.Plan
  alias Trivium.Types.ProjectContext

  @spec build(String.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def build(spec, opts) do
    %ProjectContext{path: project_path} = ctx = Keyword.fetch!(opts, :project_context)

    with {:ok, base_ref} <- current_head(project_path),
         {:ok, plan} <-
           Planner.run(spec,
             base_ref: base_ref,
             llm_client: opts[:llm_client],
             project_context: ctx
           ),
         {:ok, %Types.PreCheck{} = pc} <-
           PreChecker.run(plan,
             project_context: ctx,
             llm_client: opts[:llm_client]
           ),
         plan = merge_pre_check(plan, pc, spec),
         plan = %{plan | auto_execute: !!opts[:auto_execute]},
         {:ok, path} <- write_plan(project_path, plan) do
      {:ok, path}
    end
  end

  defp current_head(repo_path) do
    case System.cmd("git", ["-c", "safe.directory=*", "-C", repo_path, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> {:ok, String.trim(sha)}
      {err, _} -> {:error, {:no_base_ref, String.trim(err)}}
    end
  end

  defp merge_pre_check(%Plan{} = plan, pc, spec) do
    notes =
      case {pc.notes, pc.suggested_changes} do
        {[], []} -> "No conflicts found."
        {n, sc} -> Enum.map_join(n ++ sc, "\n", &"- #{&1}")
      end

    %{plan | pre_check_notes: notes, context: String.slice(spec, 0, 400)}
  end

  defp write_plan(project_path, %Plan{} = plan) do
    dir = Path.join(project_path, "docs/trivium")
    File.mkdir_p!(dir)
    date = plan.created_at |> DateTime.to_date() |> Date.to_iso8601()

    slug =
      plan.topic
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    path = Path.join(dir, "#{date}-#{slug}-plan.md")
    File.write!(path, PlanIO.encode(plan))
    {:ok, path}
  end
end
