defmodule Trivium.LLM.Anthropic do
  @moduledoc """
  Cliente HTTP para a API da Anthropic (Claude).

  Cada chamada é uma conversa nova — o isolamento entre agentes vem disso:
  nenhuma sessão compartilhada, nenhum histórico cruzado.
  """
  @behaviour Trivium.LLM.Client

  alias Trivium.Config

  @default_max_tokens 2048

  @impl true
  def complete(model, messages, opts \\ []) do
    body = build_body(model, messages, opts, false)

    case request(body) do
      {:ok, %{status: 200, body: resp}} -> {:ok, extract_text(resp)}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def stream(model, messages, opts, chunk_handler) do
    body = build_body(model, messages, opts, true)
    parent = self()
    ref = make_ref()

    into = fn {:data, data}, acc ->
      Enum.each(parse_sse_chunks(data), fn text ->
        chunk_handler.(text)
        send(parent, {ref, :chunk, text})
      end)

      {:cont, acc}
    end

    case Req.post(Config.api_base_url(),
           headers: headers(),
           json: body,
           into: into,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200}} ->
        collected = collect_chunks(ref, [])
        {:ok, IO.iodata_to_binary(collected)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_chunks(ref, acc) do
    receive do
      {^ref, :chunk, text} -> collect_chunks(ref, [acc, text])
    after
      0 -> acc
    end
  end

  defp request(body) do
    Req.post(Config.api_base_url(),
      headers: headers(),
      json: body,
      receive_timeout: 120_000
    )
  end

  defp headers do
    [
      {"x-api-key", Config.api_key() || ""},
      {"anthropic-version", Config.anthropic_version()},
      {"content-type", "application/json"}
    ]
  end

  @doc false
  def build_body(model, messages, opts, stream?) do
    {system, user_messages} = split_system(messages)

    base = %{
      model: model,
      max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
      messages: user_messages
    }

    base = if system, do: Map.put(base, :system, system), else: base
    if stream?, do: Map.put(base, :stream, true), else: base
  end

  @doc false
  def split_system(messages) do
    {system_msgs, rest} = Enum.split_with(messages, &(&1[:role] == "system" or &1["role"] == "system"))
    system_text = system_msgs |> Enum.map(&(&1[:content] || &1["content"])) |> Enum.join("\n\n")
    rest = Enum.map(rest, &normalize_message/1)

    case system_text do
      "" -> {nil, rest}
      text -> {text, rest}
    end
  end

  defp normalize_message(%{role: role, content: content}), do: %{role: role, content: content}
  defp normalize_message(%{"role" => role, "content" => content}), do: %{role: role, content: content}

  @doc false
  def extract_text(%{"content" => parts}) when is_list(parts) do
    parts
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("", & &1["text"])
  end

  def extract_text(_), do: ""

  @doc false
  def parse_sse_chunks(data) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.flat_map(fn "data: " <> payload ->
      case Jason.decode(payload) do
        {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} -> [text]
        _ -> []
      end
    end)
  end
end
