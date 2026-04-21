defmodule Trivium.Events do
  @moduledoc """
  Pub/sub baseado em Registry (built-in). Orchestrator publica eventos;
  Renderer (ou qualquer outro consumidor) se inscreve por `session_id`.
  """

  @registry Trivium.Events.Registry

  def subscribe(session_id) do
    Registry.register(@registry, session_id, nil)
  end

  def unsubscribe(session_id) do
    Registry.unregister(@registry, session_id)
  end

  def publish(session_id, event) do
    Registry.dispatch(@registry, session_id, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:harness_event, event})
    end)

    :ok
  end
end
