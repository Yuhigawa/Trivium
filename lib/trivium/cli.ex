defmodule Trivium.CLI do
  @moduledoc """
  Entry do escript. Parseia flags e:

  - sem `--path/--type/--task` → inicia REPL
  - com TODAS as três → one-shot project mode: avalia, imprime relatório e sai
  - com SÓ algumas → erro "all-or-none"
  """

  alias Trivium.{Config, Orchestrator, Report, REPL}
  alias Trivium.Types.ProjectContext

  @type_values %{
    "bug" => :bug_fix,
    "bug_fix" => :bug_fix,
    "feature" => :feature,
    "analysis" => :analysis
  }

  @plugin_json_path Path.expand("../../.claude-plugin/plugin.json", __DIR__)
  @external_resource @plugin_json_path
  @plugin_version (case File.read(@plugin_json_path) do
                     {:ok, json} ->
                       Jason.decode!(json) |> Map.fetch!("version")

                     {:error, reason} ->
                       IO.warn(
                         "Trivium.CLI: could not read #{@plugin_json_path} at compile time " <>
                           "(#{inspect(reason)}); plugin_version/0 will return \"0.0.0\". " <>
                           "Make sure the plugin manifest exists before compiling.",
                         []
                       )

                       "0.0.0"
                   end)

  @doc "Plugin version baked in at compile time from .claude-plugin/plugin.json."
  def plugin_version, do: @plugin_version

  @doc false
  def write_version(io \\ :stdio) do
    IO.puts(io, @plugin_version)
    :ok
  end

  def main(argv) do
    {:ok, _} = Application.ensure_all_started(:trivium)

    case argv do
      ["version" | _] -> run_version()
      ["build" | rest] -> run_build(rest)
      ["review" | rest] -> run_review(rest)
      _ -> run_legacy(argv)
    end
  end

  defp run_version do
    write_version()
    System.halt(0)
  end

  defp run_build(rest) do
    optimus =
      Optimus.new!(
        name: "trivium_build",
        description: "Generate plan + pre-check from a spec",
        allow_unknown_args: false,
        args: [
          spec: [
            value_name: "SPEC",
            help: "Path to a spec file, or '-' for stdin",
            required: true
          ]
        ],
        options: [
          path: [value_name: "DIR", long: "--path", help: "Project dir", required: true]
        ],
        flags: [
          auto_execute: [
            long: "--auto-execute",
            help: "Mark plan to auto-run /trivium-execute without human confirmation"
          ]
        ]
      )

    %{args: %{spec: spec_arg}, options: %{path: path}, flags: %{auto_execute: auto?}} =
      Optimus.parse!(optimus, rest)

    spec =
      case spec_arg do
        "-" -> IO.read(:stdio, :eof)
        file -> File.read!(file)
      end

    ctx = %Trivium.Types.ProjectContext{path: path, type: :feature, task: spec}

    case Trivium.Build.Orchestrator.build(spec, project_context: ctx, auto_execute: auto?) do
      {:ok, plan_path} ->
        IO.puts("TRIVIUM_PLAN_WRITTEN: #{plan_path}")
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "build failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run_review(rest) do
    optimus =
      Optimus.new!(
        name: "trivium_review",
        description: "Review a diff against a plan",
        allow_unknown_args: false,
        args: [
          plan: [
            value_name: "PLAN_PATH",
            help: "Path to the plan file",
            required: true
          ]
        ],
        options: [
          path: [value_name: "DIR", long: "--path", help: "Project dir (defaults to plan's repo)", required: false]
        ]
      )

    %{args: %{plan: plan_path}, options: %{path: opt_path}} = Optimus.parse!(optimus, rest)

    with {:ok, md} <- File.read(plan_path),
         {:ok, plan} <- Trivium.Build.PlanIO.decode(md),
         repo_path = opt_path || infer_repo(plan_path),
         {:ok, diff} <- git_diff(repo_path, plan.base_ref),
         :nonempty <- nonempty(diff),
         {:ok, review} <- Trivium.Build.Agents.Reviewer.run(plan, diff, []),
         review_body = format_review(review),
         {:ok, updated} <- Trivium.Build.PlanIO.append_review(md, review_body),
         new_status = if(review.verdict == :approved, do: :approved, else: :needs_work),
         {:ok, with_status} <- Trivium.Build.PlanIO.set_status(updated, new_status),
         :ok <- File.write(plan_path, with_status) do
      IO.puts(review_body)
      System.halt(if review.verdict == :approved, do: 0, else: 2)
    else
      :empty ->
        IO.puts(:stderr, "nothing to review (diff is empty)")
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "review failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp git_diff(repo, base_ref) do
    case System.cmd("git", ["-c", "safe.directory=*", "-C", repo, "diff", "#{base_ref}..HEAD"], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {err, _} -> {:error, {:git_diff_failed, String.trim(err)}}
    end
  end

  defp nonempty(diff) when byte_size(diff) > 0, do: :nonempty
  defp nonempty(_), do: :empty

  defp infer_repo(plan_path), do: plan_path |> Path.dirname() |> Path.dirname() |> Path.dirname()

  defp format_review(%Trivium.Build.Types.Review{} = r) do
    findings = if r.findings == [], do: "none", else: Enum.map_join(r.findings, "\n", &"- #{&1}")
    improvements = if r.improvements == [], do: "none", else: Enum.map_join(r.improvements, "\n", &"- #{&1}")

    """
    Verdict: #{r.verdict}

    Findings:
    #{findings}

    Improvements:
    #{improvements}
    """
  end

  defp run_legacy(argv) do
    optimus =
      Optimus.new!(
        name: "trivium",
        description: "Multi-agent task evaluator (idea-writer + tech + QA)",
        version: @plugin_version,
        allow_unknown_args: false,
        options: [
          max_attempts: [
            value_name: "N",
            short: "-m",
            long: "--max-attempts",
            help: "Max refinement attempts (default 3)",
            parser: :integer,
            required: false
          ],
          path: [
            value_name: "DIR",
            long: "--path",
            help: "Project directory (enables project mode — requires --type and --task)",
            required: false
          ],
          type: [
            value_name: "TYPE",
            long: "--type",
            help: "Task type: bug | feature | analysis (project mode only)",
            required: false
          ],
          task: [
            value_name: "TEXT",
            long: "--task",
            help: "Task description (project mode only)",
            required: false
          ]
        ],
        flags: [
          no_stream: [
            long: "--no-stream",
            help: "Disable live streaming output"
          ]
        ]
      )

    %{options: options, flags: flags} = Optimus.parse!(optimus, argv)

    if n = options[:max_attempts], do: Config.put(:max_attempts, n)

    case verify_llm_available() do
      :ok -> :ok
      {:error, msg} -> fail(msg)
    end

    case project_context_from(options) do
      :none ->
        REPL.start(stream: !flags.no_stream)

      {:ok, %ProjectContext{} = ctx} ->
        verify_project_mode_backend!()
        run_one_shot(ctx, stream: !flags.no_stream)

      {:error, msg} ->
        fail(msg)
    end
  end

  @doc false
  def project_context_from(options) do
    path = options[:path]
    type_raw = options[:type]
    task = options[:task]

    case {path, type_raw, task} do
      {nil, nil, nil} ->
        :none

      {p, t, ts} when is_binary(p) and is_binary(t) and is_binary(ts) ->
        with {:ok, type} <- parse_type(t),
             ctx = %ProjectContext{path: p, type: type, task: ts},
             {:ok, ctx} <- ProjectContext.validate(ctx) do
          {:ok, ctx}
        else
          {:error, reason} -> {:error, error_message(reason)}
        end

      _partial ->
        {:error,
         "--path, --type and --task must all be provided together, or none at all. " <>
           "Got: #{inspect(%{path: path, type: type_raw, task: task})}"}
    end
  end

  defp parse_type(raw) do
    case Map.fetch(@type_values, String.downcase(raw)) do
      {:ok, atom} ->
        {:ok, atom}

      :error ->
        {:error,
         {:invalid_type_string, raw,
          "allowed values: #{Map.keys(@type_values) |> Enum.join(", ")}"}}
    end
  end

  defp error_message({:invalid_type, t}), do: "invalid --type: #{inspect(t)}"

  defp error_message({:invalid_type_string, raw, hint}),
    do: "invalid --type: #{inspect(raw)} (#{hint})"

  defp error_message({:invalid_path, p}), do: "invalid --path: #{inspect(p)} (not a directory)"
  defp error_message(:empty_task), do: "--task must be non-empty"
  defp error_message(other), do: "invalid project context: #{inspect(other)}"

  defp run_one_shot(%ProjectContext{} = ctx, opts) do
    stream? = Keyword.get(opts, :stream, true)

    result =
      Orchestrator.evaluate(ctx.task,
        project_context: ctx,
        stream: stream?
      )

    IO.puts("")
    IO.puts(Report.format(result))

    exit_code =
      case result.status do
        :approved -> 0
        :rejected -> 2
        :error -> 1
      end

    System.halt(exit_code)
  end

  defp verify_project_mode_backend! do
    case Config.llm_client() do
      Trivium.LLM.ClaudeCLI ->
        :ok

      other ->
        fail(
          "project mode requires llm_client Trivium.LLM.ClaudeCLI, got #{inspect(other)}. " <>
            "Tool-use support for other backends is not implemented yet."
        )
    end
  end

  defp verify_llm_available do
    case Config.llm_client() do
      Trivium.LLM.Anthropic ->
        if Config.api_key() in [nil, ""],
          do: {:error, "ANTHROPIC_API_KEY not set in environment"},
          else: :ok

      Trivium.LLM.ClaudeCLI ->
        case System.cmd("claude", ["--version"], stderr_to_stdout: true) do
          {_, 0} -> :ok
          _ -> {:error, "`claude` CLI not found on PATH or not runnable"}
        end

      _ ->
        :ok
    end
  end

  defp fail(msg) do
    IO.puts(:stderr, "error: #{msg}")
    System.halt(1)
  end
end
