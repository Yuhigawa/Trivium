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

  def main(argv) do
    {:ok, _} = Application.ensure_all_started(:trivium)

    optimus =
      Optimus.new!(
        name: "trivium",
        description: "Multi-agent task evaluator (idea-writer + tech + QA)",
        version: "0.1.0",
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
