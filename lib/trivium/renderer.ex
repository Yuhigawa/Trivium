defmodule Trivium.Renderer do
  @moduledoc """
  Consumidor de eventos que imprime progresso no stdout com cores.
  Roda em processo próprio por sessão.
  """

  alias Trivium.Events

  @colors %{
    idea_writer: :cyan,
    technical_researcher: :yellow,
    qa: :magenta
  }

  @labels %{
    idea_writer: "idea",
    technical_researcher: "tech",
    qa: "qa"
  }

  def start(session_id, opts \\ []) do
    parent = self()

    pid =
      spawn_link(fn ->
        Events.subscribe(session_id)
        send(parent, :renderer_ready)
        loop(opts)
      end)

    receive do
      :renderer_ready -> :ok
    after
      1_000 -> :ok
    end

    pid
  end

  defp loop(opts) do
    receive do
      {:harness_event, event} ->
        render(event, opts)
        loop(opts)

      :stop ->
        :ok
    end
  end

  def stop(renderer_pid) do
    send(renderer_pid, :stop)
  end

  defp render(:session_started, _opts) do
    write([:bright, "Starting evaluation...\n", :reset])
  end

  defp render({:attempt_started, n, total}, _opts) do
    write([:bright, "\n[attempt #{n}/#{total}]\n", :reset])
  end

  defp render({:agent_started, role}, _opts) do
    color = Map.get(@colors, role, :white)
    label = Map.get(@labels, role, Atom.to_string(role))
    write([color, "[#{label}] ", :reset, "working... "])
  end

  defp render({:agent_token, _role, _chunk}, %{stream: true}) do
    IO.write(".")
  end

  defp render({:agent_token, _role, _chunk}, _opts), do: :ok

  defp render({:agent_finished, role, :idea, _idea}, _opts) do
    color = Map.get(@colors, role, :white)
    write([" ", color, "done (idea generated)\n", :reset])
  end

  defp render({:agent_finished, role, :review, review}, _opts) do
    color = Map.get(@colors, role, :white)
    write([" ", color, "done → score #{review.score}/10\n", :reset])
  end

  defp render({:agent_error, role, reason}, _opts) do
    write([:red, "[#{role}] error: #{inspect(reason)}\n", :reset])
  end

  defp render({:scores_computed, _reviews, :pass}, _opts) do
    write([:green, "\n✓ approved\n", :reset])
  end

  defp render({:scores_computed, _reviews, :fail}, _opts) do
    write([:red, "\n✗ failed — refining\n", :reset])
  end

  defp render({:session_finished, _result}, _opts), do: :ok
  defp render(_other, _opts), do: :ok

  defp write(io) do
    IO.write(IO.ANSI.format(io))
  end
end
