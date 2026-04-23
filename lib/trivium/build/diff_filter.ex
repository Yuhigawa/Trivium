defmodule Trivium.Build.DiffFilter do
  @moduledoc """
  Strips noise from a `git diff` before it reaches the Reviewer LLM.

  Removes whole-file diffs for lockfiles, binary blobs, vendored
  dependencies, build artefacts, and the escript binary itself. Pure
  Elixir, deterministic, no LLM in the loop. The original diff stays
  reproducible by re-running `git diff <base_ref>..HEAD` — this filter
  only governs what we *send* to the agent.
  """

  @drop_paths [
    ~r{(^|/)mix\.lock$},
    ~r{(^|/)package-lock\.json$},
    ~r{(^|/)yarn\.lock$},
    ~r{(^|/)pnpm-lock\.yaml$},
    ~r{(^|/)Cargo\.lock$},
    ~r{(^|/)Gemfile\.lock$},
    ~r{(^|/)poetry\.lock$},
    ~r{(^|/)composer\.lock$},
    ~r{(^|/)deps/},
    ~r{(^|/)_build/},
    ~r{(^|/)node_modules/},
    ~r{(^|/)target/},
    ~r{(^|/)vendor/},
    ~r{(^|/)dist/},
    ~r{(^|/)build/},
    ~r{(^|/)\.next/},
    ~r{^trivium$},
    # Trivium's own artefacts — Reviewer already receives the plan separately,
    # and the spec is upstream context that doesn't change between build/review.
    ~r{(^|/)docs/trivium/},
    ~r{^trivium-spec.*\.md$},
    ~r{(^|/)\.smoke-spec\.md$}
  ]

  @spec filter(binary()) :: binary()
  def filter(diff) when is_binary(diff) do
    diff
    |> split_file_blocks()
    |> Enum.reject(&drop?/1)
    |> Enum.join("")
  end

  defp split_file_blocks(""), do: []

  defp split_file_blocks(diff) do
    String.split(diff, ~r/(?=^diff --git )/m, trim: true)
  end

  defp drop?(block) do
    binary_diff?(block) or dropped_path?(block)
  end

  defp binary_diff?(block), do: String.contains?(block, "\nBinary files ")

  defp dropped_path?(block) do
    case Regex.run(~r/^diff --git a\/(\S+) b\/\S+/m, block) do
      [_, path] -> Enum.any?(@drop_paths, &Regex.match?(&1, path))
      _ -> false
    end
  end
end
