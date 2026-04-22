defmodule Trivium.Build.PlanIO do
  @moduledoc """
  Encode/decode the plan markdown artefact.

  Format: YAML-ish front-matter (`key: value` per line) between `---` fences,
  followed by a markdown body with `## Context`, `## Pre-check notes`, `## Steps`,
  optionally `## Review` (and `## Review (N)`).

  Steps use GFM checkboxes:

      - [ ] **1. title**
            **Files**: `path/a.ex`, `path/b.ex`
            **Acceptance**: criterion
            **Notes**: optional notes
  """

  alias Trivium.Build.Types.{Plan, Step}

  @status_atoms ~w(draft in_progress review_pending approved needs_work)a
  @status_strings Enum.map(@status_atoms, &Atom.to_string/1)

  # ---- encode ----

  @spec encode(Plan.t()) :: String.t()
  def encode(%Plan{} = p) do
    """
    ---
    topic: #{escape(p.topic)}
    created: #{DateTime.to_iso8601(p.created_at)}
    base_ref: #{p.base_ref}
    status: #{p.status}
    trivium_version: #{p.trivium_version}
    ---

    # Plan: #{p.topic}

    ## Context
    #{p.context || ""}

    ## Pre-check notes
    #{p.pre_check_notes || ""}

    ## Steps

    #{Enum.map_join(p.steps, "\n\n", &encode_step/1)}

    ## Review
    """
  end

  defp encode_step(%Step{} = s) do
    box = if s.done?, do: "x", else: " "
    files = if s.files == [], do: "", else: Enum.map_join(s.files, ", ", &"`#{&1}`")

    notes_line =
      if is_binary(s.notes) and s.notes != "" do
        "\n      **Notes**: #{s.notes}"
      else
        ""
      end

    """
    - [#{box}] **#{s.index}. #{s.title}**
          **Files**: #{files}
          **Acceptance**: #{s.acceptance || ""}#{notes_line}
    """
    |> String.trim_trailing()
  end

  defp escape(s), do: String.replace(s, "\n", " ")

  # ---- decode ----

  @spec decode(String.t()) :: {:ok, Plan.t()} | {:error, term()}
  def decode(markdown) when is_binary(markdown) do
    with {:ok, fm, body} <- split_front_matter(markdown),
         {:ok, fm_map} <- parse_front_matter(fm),
         {:ok, status} <- parse_status(fm_map["status"]),
         {:ok, created_at, _} <- DateTime.from_iso8601(fm_map["created"] || ""),
         steps <- parse_steps(body) do
      {:ok,
       %Plan{
         topic: fm_map["topic"] || "",
         base_ref: fm_map["base_ref"] || "",
         status: status,
         created_at: created_at,
         context: section(body, "Context"),
         pre_check_notes: section(body, "Pre-check notes"),
         trivium_version: fm_map["trivium_version"] || "0.0.0",
         steps: steps
       }}
    end
  end

  defp split_front_matter("---\n" <> rest) do
    case String.split(rest, "\n---", parts: 2) do
      [fm, body] -> {:ok, fm, body}
      _ -> {:error, :no_front_matter}
    end
  end

  defp split_front_matter(_), do: {:error, :no_front_matter}

  defp parse_front_matter(fm) do
    map =
      fm
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, ":", parts: 2) do
          [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
          _ -> acc
        end
      end)

    {:ok, map}
  end

  defp parse_status(s) when s in @status_strings, do: {:ok, String.to_existing_atom(s)}
  defp parse_status(other), do: {:error, {:invalid_status, other}}

  defp section(body, name) do
    case Regex.run(~r/##\s+#{Regex.escape(name)}\n(.*?)(?=\n##\s|\z)/s, body) do
      [_, text] -> text |> String.trim() |> nil_if_empty()
      _ -> nil
    end
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  defp parse_steps(body) do
    case section(body, "Steps") do
      nil ->
        []

      text ->
        text
        |> String.split(~r/\n(?=- \[)/)
        |> Enum.map(&parse_step/1)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp parse_step(block) do
    with [_, box, idx, title] <-
           Regex.run(~r/- \[( |x)\] \*\*(\d+)\.\s*(.+?)\*\*/, block),
         {n, _} <- Integer.parse(idx) do
      %Step{
        index: n,
        title: String.trim(title),
        files: extract_files(block),
        acceptance: extract_field(block, "Acceptance"),
        notes: extract_field(block, "Notes"),
        done?: box == "x"
      }
    else
      _ -> nil
    end
  end

  defp extract_files(block) do
    case Regex.run(~r/\*\*Files\*\*:\s*(.+)/, block) do
      [_, line] ->
        Regex.scan(~r/`([^`]+)`/, line) |> Enum.map(fn [_, f] -> f end)

      _ ->
        []
    end
  end

  defp extract_field(block, name) do
    case Regex.run(~r/\*\*#{Regex.escape(name)}\*\*:\s*(.+)/, block) do
      [_, val] -> String.trim(val)
      _ -> nil
    end
  end

  # ---- mutations ----

  @spec set_status(String.t(), Plan.status()) :: {:ok, String.t()} | {:error, term()}
  def set_status(markdown, status) when status in @status_atoms do
    case Regex.replace(~r/^status:.*$/m, markdown, "status: #{status}", global: false) do
      ^markdown -> {:error, :status_line_not_found}
      updated -> {:ok, updated}
    end
  end

  @spec tick_step(String.t(), pos_integer()) :: {:ok, String.t()} | {:error, term()}
  def tick_step(markdown, index) do
    pattern = ~r/- \[ \] \*\*#{index}\./

    case Regex.replace(pattern, markdown, "- [x] **#{index}.", global: false) do
      ^markdown -> {:error, {:step_not_found, index}}
      updated -> {:ok, updated}
    end
  end

  @spec append_review(String.t(), String.t()) :: {:ok, String.t()}
  def append_review(markdown, body) do
    n = count_reviews(markdown) + 1
    header = if n == 1, do: "## Review", else: "## Review (#{n})"

    updated =
      if String.contains?(markdown, "\n## Review\n") do
        if n == 1 do
          Regex.replace(~r/## Review\n\z/, markdown, "## Review\n#{body}\n")
        else
          markdown <> "\n#{header}\n#{body}\n"
        end
      else
        markdown <> "\n#{header}\n#{body}\n"
      end

    {:ok, updated}
  end

  defp count_reviews(markdown) do
    cond do
      Regex.match?(~r/## Review \(\d+\)/, markdown) ->
        Regex.scan(~r/## Review \((\d+)\)/, markdown)
        |> Enum.map(fn [_, n] -> String.to_integer(n) end)
        |> Enum.max()

      Regex.match?(~r/## Review\n[^\n]/, markdown) ->
        1

      true ->
        0
    end
  end
end
