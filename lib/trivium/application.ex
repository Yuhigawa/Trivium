defmodule Trivium.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: Trivium.Events.Registry},
      {Task.Supervisor, name: Trivium.AgentTasks}
    ]

    opts = [strategy: :one_for_one, name: Trivium.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
