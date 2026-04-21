defmodule Trivium.LLM.Mock do
  @moduledoc """
  Cliente LLM determinístico para testes. Usa um Agent para guardar um roteiro de
  respostas por papel. Grava todas as mensagens recebidas para asserts de isolamento.
  """
  @behaviour Trivium.LLM.Client

  use Agent

  def start_link(_ \\ []) do
    Agent.start_link(fn -> %{scripts: %{}, calls: []} end, name: __MODULE__)
  end

  @doc """
  Define um roteiro de respostas para um modelo/papel específico.
  As respostas são consumidas em ordem a cada chamada.
  """
  def set_script(key, responses) when is_list(responses) do
    Agent.update(__MODULE__, fn state ->
      scripts = Map.put(state.scripts, key, responses)
      %{state | scripts: scripts}
    end)
  end

  def calls do
    Agent.get(__MODULE__, & &1.calls)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %{scripts: %{}, calls: []} end)
  end

  @impl true
  def complete(model, messages, opts) do
    key = Keyword.get(opts, :role, model)

    Agent.get_and_update(__MODULE__, fn state ->
      response =
        case Map.get(state.scripts, key, []) do
          [] -> "{\"score\": 8, \"justification\": \"mock default\"}"
          [head | _rest] -> head
        end

      new_scripts =
        Map.update(state.scripts, key, [], fn
          [_head | rest] -> rest
          [] -> []
        end)

      call = %{model: model, messages: messages, opts: opts, response: response}
      {{:ok, response}, %{state | scripts: new_scripts, calls: [call | state.calls]}}
    end)
  end

  @impl true
  def stream(model, messages, opts, chunk_handler) do
    case complete(model, messages, opts) do
      {:ok, text} ->
        chunk_handler.(text)
        {:ok, text}

      err ->
        err
    end
  end
end
