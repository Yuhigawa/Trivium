defmodule Trivium.CLI do
  @moduledoc "Entry do escript. Parseia flags e dispara o REPL."

  alias Trivium.{Config, REPL}

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

    case verify_llm_available() do
      :ok -> :ok
      {:error, msg} -> IO.puts(:stderr, "error: #{msg}") ; System.halt(1)
    end

    if n = options[:max_attempts], do: Config.put(:max_attempts, n)

    repl_opts = [stream: !flags.no_stream]
    REPL.start(repl_opts)
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
end
