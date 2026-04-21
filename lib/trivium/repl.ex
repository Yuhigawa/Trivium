defmodule Trivium.REPL do
  @moduledoc """
  Loop interativo. Lê a tarefa do usuário, dispara `Orchestrator.evaluate/2`,
  mostra logs via Renderer e imprime o relatório final.
  """

  alias Trivium.{Orchestrator, Renderer, Report}

  def start(opts \\ []) do
    print_banner()
    loop(opts)
  end

  defp loop(opts) do
    case IO.gets("\n> ") do
      :eof ->
        IO.puts("\nbye.")
        :ok

      {:error, reason} ->
        IO.puts("\nerror reading input: #{inspect(reason)}")
        :ok

      data ->
        task = String.trim(data)

        cond do
          task == "" ->
            loop(opts)

          task in ["quit", "exit", ":q"] ->
            IO.puts("bye.")
            :ok

          true ->
            run_session(task, opts)
            loop(opts)
        end
    end
  end

  defp run_session(task, opts) do
    session_id = make_ref()
    stream? = Keyword.get(opts, :stream, true)
    renderer = Renderer.start(session_id, stream: stream?)

    eval_opts =
      opts
      |> Keyword.put(:session_id, session_id)
      |> Keyword.put(:stream, stream?)

    result = Orchestrator.evaluate(task, eval_opts)

    Process.sleep(50)
    Renderer.stop(renderer)

    IO.puts("\n")
    IO.puts(Report.format(result))
  end

  defp print_banner do
    IO.puts("""
    Trivium v0.1 — multi-agent task evaluator
    Type your task. Ctrl+D or `exit` to quit.
    """)
  end
end
