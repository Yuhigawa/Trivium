defmodule Trivium.LLM.ClaudeCLI do
  @moduledoc """
  Cliente LLM que invoca o binário `claude` (Claude Code CLI) em modo headless
  (`-p`), reutilizando a sessão/subscription logada no host.

  Como shelamos o processo, redirecionamos stdin para /dev/null — caso contrário
  o claude CLI espera 3s por input antes de imprimir um warning no stdout, o que
  quebra o parser.
  """
  @behaviour Trivium.LLM.Client

  @impl true
  def complete(model, messages, opts \\ []) do
    {system, user_text} = split_messages(messages)
    args = build_args(model, system, opts)
    full_args = args ++ [user_text]

    quoted = full_args |> Enum.map(&shell_quote/1) |> Enum.join(" ")
    shell_cmd = "claude #{quoted} </dev/null"

    case System.cmd("sh", ["-c", shell_cmd], stderr_to_stdout: true) do
      {stdout, 0} -> parse_output(stdout)
      {stdout, code} -> {:error, {:claude_exit, code, stdout}}
    end
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

  @doc false
  def split_messages(messages) do
    {systems, users} =
      Enum.split_with(messages, fn m ->
        role = m[:role] || m["role"]
        role == "system"
      end)

    system_text =
      systems
      |> Enum.map_join("\n\n", &(&1[:content] || &1["content"]))

    user_text =
      users
      |> Enum.map_join("\n\n", fn m ->
        content = m[:content] || m["content"]
        role = m[:role] || m["role"]

        if role == "assistant", do: "[assistant said previously]: #{content}", else: content
      end)

    {system_text, user_text}
  end

  @doc false
  def build_args(model, system_text, _opts \\ []) do
    base = [
      "-p",
      "--model", model,
      "--output-format", "json",
      "--allowedTools", ""
    ]

    case system_text do
      "" -> base
      text -> base ++ ["--append-system-prompt", text]
    end
  end

  @doc false
  def parse_output(stdout) do
    trimmed = String.trim(stdout)

    case Jason.decode(trimmed) do
      {:ok, %{"result" => text}} when is_binary(text) -> {:ok, text}
      {:ok, %{"content" => text}} when is_binary(text) -> {:ok, text}
      {:ok, other} -> {:error, {:unexpected_json, other}}
      {:error, _} -> {:ok, trimmed}
    end
  end

  @doc false
  def shell_quote(s) do
    "'" <> String.replace(s, "'", "'\\''") <> "'"
  end
end
