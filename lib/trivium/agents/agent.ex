defmodule Trivium.Agents.Agent do
  @moduledoc """
  Behaviour comum aos agentes. Cada agente é um módulo stateless com `run/2`
  que invoca o LLM e devolve `{:ok, payload}` ou `{:error, reason}`.
  """

  @type role :: :idea_writer | :technical_researcher | :qa

  @callback role() :: role()

  @doc """
  Extrai um bloco JSON `{"score": N, "justification": "..."}` de uma string,
  tolerando prefixos conversacionais ou blocos em markdown.
  """
  def parse_review(text, role) do
    with {:ok, json} <- find_json(text),
         {:ok, %{"score" => score, "justification" => justification}} <- Jason.decode(json) do
      case clamp_score(score) do
        {:ok, s} ->
          {:ok,
           %Trivium.Types.Review{
             role: role,
             score: s,
             justification: justification
           }}

        err ->
          err
      end
    else
      :error -> {:error, {:no_json_found, text}}
      {:error, %Jason.DecodeError{} = e} -> {:error, {:invalid_json, e}}
      {:ok, other} -> {:error, {:missing_fields, other}}
      err -> {:error, err}
    end
  end

  defp find_json(text) do
    case Regex.run(~r/\{[^{}]*"score"[^{}]*\}/s, text) do
      [match] -> {:ok, match}
      nil -> :error
    end
  end

  defp clamp_score(n) when is_integer(n) and n >= 1 and n <= 10, do: {:ok, n}
  defp clamp_score(n) when is_float(n), do: clamp_score(round(n))
  defp clamp_score(n), do: {:error, {:score_out_of_range, n}}
end
