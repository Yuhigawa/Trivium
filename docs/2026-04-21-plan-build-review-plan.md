# Trivium plan/build/review pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three new commands to Trivium — `/trivium-build`, `/trivium-execute`, `/trivium-review` — that take a spec through plan generation, pre-implementation validation, and post-implementation review, producing a single durable plan artefact.

**Architecture:** Two new singular agents (`Planner`, `Reviewer`) plus one reused-pattern agent (`PreChecker`), one sequential `BuildOrchestrator`, a markdown plan encoder/decoder under a new `Trivium.Build` namespace, two new CLI subcommands, and three slash commands that orchestrate the handoff via a `TRIVIUM_PLAN_WRITTEN:` marker.

**Tech Stack:** Elixir, Optimus (CLI), `Trivium.LLM.ClaudeCLI`, Jason, ExUnit, GFM markdown plan artefact.

---

## File structure

**New files:**
- `lib/trivium/build/types.ex` — namespaced structs: `Plan`, `Step`, `PreCheck`, `Review`
- `lib/trivium/build/plan_io.ex` — encode/decode plan markdown (front-matter + steps + status mutation)
- `lib/trivium/build/agents/planner.ex`
- `lib/trivium/build/agents/pre_checker.ex`
- `lib/trivium/build/agents/reviewer.ex`
- `lib/trivium/build/orchestrator.ex`
- `commands/trivium-build.md`
- `commands/trivium-execute.md`
- `commands/trivium-review.md`
- `test/trivium/build/plan_io_test.exs`
- `test/trivium/build/agents/planner_test.exs`
- `test/trivium/build/agents/pre_checker_test.exs`
- `test/trivium/build/agents/reviewer_test.exs`
- `test/trivium/build/orchestrator_test.exs`

**Modified files:**
- `lib/trivium/cli.ex` — add `build` and `review` subcommands (Optimus subcommand mode); preserve REPL/one-shot defaults
- `lib/trivium/llm/mock.ex` — add canned responses keyed by new agent roles
- `.claude-plugin/plugin.json` — bump version `0.1.0 → 0.2.0`
- `README.md` — document the new pipeline + commands

---

## Conventions used by this plan

- All new modules live under `Trivium.Build.*` to keep the new pipeline isolated from the existing 3-agent gate (`Trivium.Agents.*`, `Trivium.Orchestrator`).
- `Trivium.Build.Types.Review` is **distinct** from the existing `Trivium.Types.Review` (which has `:role`/`:score`). Always disambiguate by alias: `alias Trivium.Build.Types.Review, as: BuildReview`.
- Plan files live at `docs/trivium/YYYY-MM-DD-<slug>-plan.md` in the **target project's** working dir, not in this repo.
- Tests follow the existing pattern in `test/trivium/` using `Trivium.LLM.Mock` configured per test.

---

### Task 1: Add `Trivium.Build.Types`

**Files:**
- Create: `lib/trivium/build/types.ex`

- [ ] **Step 1: Write the file**

```elixir
defmodule Trivium.Build.Types do
  @moduledoc "Structs for the plan/build/review pipeline. Isolated from the gate types."

  defmodule Step do
    @enforce_keys [:index, :title]
    defstruct [:index, :title, files: [], acceptance: nil, notes: nil, done?: false]

    @type t :: %__MODULE__{
            index: pos_integer(),
            title: String.t(),
            files: [String.t()],
            acceptance: String.t() | nil,
            notes: String.t() | nil,
            done?: boolean()
          }
  end

  defmodule Plan do
    @enforce_keys [:topic, :base_ref, :steps, :status, :created_at]
    defstruct [
      :topic,
      :base_ref,
      :steps,
      :status,
      :created_at,
      context: nil,
      pre_check_notes: nil,
      trivium_version: "0.1.0"
    ]

    @type status :: :draft | :in_progress | :review_pending | :approved | :needs_work
    @type t :: %__MODULE__{
            topic: String.t(),
            base_ref: String.t(),
            steps: [Trivium.Build.Types.Step.t()],
            status: status(),
            created_at: DateTime.t(),
            context: String.t() | nil,
            pre_check_notes: String.t() | nil,
            trivium_version: String.t()
          }
  end

  defmodule PreCheck do
    @enforce_keys [:verdict]
    defstruct [:verdict, notes: [], suggested_changes: []]

    @type verdict :: :ok | :revise
    @type t :: %__MODULE__{
            verdict: verdict(),
            notes: [String.t()],
            suggested_changes: [String.t()]
          }
  end

  defmodule Review do
    @enforce_keys [:verdict]
    defstruct [:verdict, findings: [], improvements: []]

    @type verdict :: :approved | :needs_work
    @type t :: %__MODULE__{
            verdict: verdict(),
            findings: [String.t()],
            improvements: [String.t()]
          }
  end
end
```

- [ ] **Step 2: Compile to verify**

Run: `docker compose run --rm trivium mix compile`
Expected: clean compile, no warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/trivium/build/types.ex
git commit -m "feat(build): add Plan/Step/PreCheck/Review types"
```

---

### Task 2: Plan markdown encode/decode (`Trivium.Build.PlanIO`)

**Files:**
- Create: `lib/trivium/build/plan_io.ex`
- Create: `test/trivium/build/plan_io_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Trivium.Build.PlanIOTest do
  use ExUnit.Case, async: true

  alias Trivium.Build.PlanIO
  alias Trivium.Build.Types.{Plan, Step}

  @sample %Plan{
    topic: "Add X to Y",
    base_ref: "a1b2c3d4",
    status: :draft,
    created_at: ~U[2026-04-21 15:30:00Z],
    context: "Two-line context.",
    pre_check_notes: "No conflicts found.",
    trivium_version: "0.2.0",
    steps: [
      %Step{
        index: 1,
        title: "Add module Foo",
        files: ["lib/foo.ex"],
        acceptance: "mix compile passes; module exported",
        notes: nil
      },
      %Step{
        index: 2,
        title: "Wire Foo into bar",
        files: ["lib/bar.ex"],
        acceptance: "Bar.run/0 returns :ok",
        notes: "Reuse existing pattern in baz.ex"
      }
    ]
  }

  test "encode/decode round-trip preserves all fields" do
    md = PlanIO.encode(@sample)
    {:ok, parsed} = PlanIO.decode(md)

    assert parsed.topic == @sample.topic
    assert parsed.base_ref == @sample.base_ref
    assert parsed.status == @sample.status
    assert parsed.context == @sample.context
    assert parsed.pre_check_notes == @sample.pre_check_notes
    assert length(parsed.steps) == 2
    [s1, s2] = parsed.steps
    assert s1.index == 1
    assert s1.title == "Add module Foo"
    assert s1.files == ["lib/foo.ex"]
    assert s1.acceptance =~ "mix compile passes"
    assert s1.done? == false
    assert s2.notes =~ "Reuse existing pattern"
  end

  test "decode parses checkbox state into done?" do
    md = """
    ---
    topic: T
    base_ref: abc
    status: in_progress
    created: 2026-04-21T00:00:00Z
    trivium_version: 0.2.0
    ---

    # Plan: T

    ## Steps

    - [x] **1. done step**
          **Files**: `a.ex`
          **Acceptance**: ok

    - [ ] **2. pending step**
          **Files**: `b.ex`
          **Acceptance**: ok
    """

    {:ok, plan} = PlanIO.decode(md)
    [s1, s2] = plan.steps
    assert s1.done? == true
    assert s2.done? == false
    assert plan.status == :in_progress
  end

  test "set_status mutates only the status line" do
    md = PlanIO.encode(@sample)
    {:ok, mutated} = PlanIO.set_status(md, :in_progress)
    {:ok, parsed} = PlanIO.decode(mutated)
    assert parsed.status == :in_progress
    assert parsed.topic == @sample.topic
  end

  test "tick_step marks the matching index as done" do
    md = PlanIO.encode(@sample)
    {:ok, mutated} = PlanIO.tick_step(md, 1)
    {:ok, parsed} = PlanIO.decode(mutated)
    assert Enum.at(parsed.steps, 0).done? == true
    assert Enum.at(parsed.steps, 1).done? == false
  end

  test "append_review adds a Review section" do
    md = PlanIO.encode(@sample)

    {:ok, mutated} =
      PlanIO.append_review(md, """
      Verdict: approved
      Findings: none
      """)

    assert mutated =~ "## Review"
    assert mutated =~ "Verdict: approved"
  end

  test "append_review on a plan that already has one appends '## Review (2)'" do
    md = PlanIO.encode(@sample)
    {:ok, once} = PlanIO.append_review(md, "first review")
    {:ok, twice} = PlanIO.append_review(once, "second review")
    assert twice =~ "## Review (2)"
    assert twice =~ "first review"
    assert twice =~ "second review"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `docker compose run --rm trivium mix test test/trivium/build/plan_io_test.exs`
Expected: FAIL — module `Trivium.Build.PlanIO` is not loaded.

- [ ] **Step 3: Implement `PlanIO`**

```elixir
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
      nil -> []
      text -> text |> String.split(~r/\n(?=- \[)/) |> Enum.map(&parse_step/1) |> Enum.reject(&is_nil/1)
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
        # The encode template includes an empty "## Review" placeholder. First
        # call fills it; subsequent calls append numbered sections.
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `docker compose run --rm trivium mix test test/trivium/build/plan_io_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/trivium/build/plan_io.ex test/trivium/build/plan_io_test.exs
git commit -m "feat(build): plan markdown encode/decode with status mutations"
```

---

### Task 3: `Planner` agent

**Files:**
- Create: `lib/trivium/build/agents/planner.ex`
- Create: `test/trivium/build/agents/planner_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Trivium.Build.Agents.PlannerTest do
  use ExUnit.Case, async: true

  alias Trivium.Build.Agents.Planner
  alias Trivium.Build.Types.{Plan, Step}
  alias Trivium.Types.ProjectContext

  @canned_steps """
  Here is the plan.

  ```json
  {
    "topic": "Add cache to fetcher",
    "steps": [
      {"title": "Add ETS table", "files": ["lib/cache.ex"], "acceptance": "Cache.start_link/0 returns {:ok, pid}"},
      {"title": "Wire fetcher to cache", "files": ["lib/fetcher.ex"], "acceptance": "Fetcher.fetch/1 hits cache on second call"}
    ]
  }
  ```
  """

  test "run/2 turns spec text into a Plan with parsed steps" do
    mock = fn _model, _msgs, _opts -> {:ok, @canned_steps} end
    ctx = %ProjectContext{path: System.tmp_dir!(), type: :feature, task: "Add cache"}

    {:ok, %Plan{} = plan} =
      Planner.run("spec text", base_ref: "deadbeef", llm_client: stub_client(mock), project_context: ctx)

    assert plan.topic == "Add cache to fetcher"
    assert plan.base_ref == "deadbeef"
    assert plan.status == :draft
    assert length(plan.steps) == 2
    [s1 | _] = plan.steps
    assert %Step{index: 1, title: "Add ETS table"} = s1
    assert s1.files == ["lib/cache.ex"]
    assert s1.acceptance =~ "Cache.start_link/0"
  end

  test "run/2 returns {:error, _} when LLM output has no JSON block" do
    mock = fn _, _, _ -> {:ok, "No structured output here."} end

    assert {:error, _} =
             Planner.run("spec", base_ref: "abc", llm_client: stub_client(mock))
  end

  defp stub_client(complete_fun) do
    Module.concat(["TestStub", :crypto.strong_rand_bytes(8) |> Base.encode16()])
    |> tap(fn mod ->
      Code.eval_string("""
      defmodule #{inspect(mod)} do
        def complete(model, messages, opts), do: (#{inspect(complete_fun)}).(model, messages, opts)
        def stream(model, messages, opts, _h), do: complete(model, messages, opts)
      end
      """)
    end)
  end
end
```

> Note: the inline stub-module helper above is awkward. If the project already has a cleaner pattern (e.g., `Trivium.LLM.Mock` accepts per-test canned responses), replace `stub_client/1` with that pattern. Read `lib/trivium/llm/mock.ex` before implementing this test and adapt to whichever convention is in use.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose run --rm trivium mix test test/trivium/build/agents/planner_test.exs`
Expected: FAIL — `Trivium.Build.Agents.Planner` not loaded.

- [ ] **Step 3: Implement the Planner**

```elixir
defmodule Trivium.Build.Agents.Planner do
  @moduledoc """
  Turns an approved spec into a structured `%Plan{}` of ordered steps.

  Output JSON contract:

      {"topic": "...", "steps": [{"title", "files", "acceptance", "notes"?}]}
  """

  alias Trivium.Config
  alias Trivium.Build.Types.{Plan, Step}
  alias Trivium.Types.ProjectContext

  @system_prompt """
  Você é um planner sênior. Receba uma especificação aprovada e produza um
  plano de implementação com passos ORDENADOS e ATÔMICOS (cada passo é um
  commit). Para cada passo dê:

  - title: descrição curta (≤ 80 chars)
  - files: lista de arquivos a criar/editar (paths exatos quando souber)
  - acceptance: critério verificável (teste passando, mix compile, etc.)
  - notes (opcional): contexto extra pro implementador

  Se tiver acesso ao código (Read/Grep/Glob), use-o para identificar arquivos
  e padrões existentes a respeitar.

  Formato OBRIGATÓRIO no fim da resposta — JSON em bloco markdown:

  ```json
  {"topic": "<short topic>", "steps": [{"title": "...", "files": ["..."], "acceptance": "..."}]}
  ```
  """

  def run(spec, opts) do
    base_ref = Keyword.fetch!(opts, :base_ref)
    client = Keyword.get(opts, :llm_client, Config.llm_client())
    project_context = Keyword.get(opts, :project_context)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: "Especificação aprovada:\n\n#{spec}"}
    ]

    model = Config.model_for(:idea_writer)
    llm_opts = llm_opts(project_context)

    with {:ok, text} <- client.complete(model, messages, llm_opts),
         {:ok, json} <- find_json(text),
         {:ok, %{"topic" => topic, "steps" => raw_steps}} <- Jason.decode(json) do
      steps =
        raw_steps
        |> Enum.with_index(1)
        |> Enum.map(fn {s, i} ->
          %Step{
            index: i,
            title: s["title"] || "(untitled)",
            files: s["files"] || [],
            acceptance: s["acceptance"],
            notes: s["notes"]
          }
        end)

      {:ok,
       %Plan{
         topic: topic,
         base_ref: base_ref,
         steps: steps,
         status: :draft,
         created_at: DateTime.utc_now(),
         trivium_version: Application.spec(:trivium, :vsn) |> to_string()
       }}
    else
      {:error, _} = e -> e
      :error -> {:error, :no_json_in_planner_output}
      other -> {:error, {:planner_unexpected, other}}
    end
  end

  defp find_json(text) do
    case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
      [_, json] -> {:ok, json}
      _ -> :error
    end
  end

  defp llm_opts(nil), do: [role: :planner]

  defp llm_opts(%ProjectContext{path: path}),
    do: [role: :planner, add_dir: path, allowed_tools: "Read Grep Glob"]
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `docker compose run --rm trivium mix test test/trivium/build/agents/planner_test.exs`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/trivium/build/agents/planner.ex test/trivium/build/agents/planner_test.exs
git commit -m "feat(build): Planner agent — spec -> ordered steps"
```

---

### Task 4: `PreChecker` agent

**Files:**
- Create: `lib/trivium/build/agents/pre_checker.ex`
- Create: `test/trivium/build/agents/pre_checker_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Trivium.Build.Agents.PreCheckerTest do
  use ExUnit.Case, async: true

  alias Trivium.Build.Agents.PreChecker
  alias Trivium.Build.Types.{Plan, Step, PreCheck}
  alias Trivium.Types.ProjectContext

  @plan %Plan{
    topic: "Add X",
    base_ref: "abc",
    status: :draft,
    created_at: DateTime.utc_now(),
    steps: [%Step{index: 1, title: "Touch foo", files: ["lib/foo.ex"], acceptance: "compiles"}]
  }

  test "ok verdict surfaces empty notes" do
    canned = ~s({"verdict": "ok", "notes": [], "suggested_changes": []})
    mock = fn _, _, _ -> {:ok, "```json\n#{canned}\n```"} end
    ctx = %ProjectContext{path: System.tmp_dir!(), type: :feature, task: "x"}

    {:ok, %PreCheck{verdict: :ok, notes: [], suggested_changes: []}} =
      PreChecker.run(@plan, project_context: ctx, llm_client: stub(mock))
  end

  test "revise verdict surfaces notes and suggestions" do
    canned = ~s({"verdict": "revise", "notes": ["lib/foo.ex já é grande demais"], "suggested_changes": ["Split foo.ex first"]})
    mock = fn _, _, _ -> {:ok, "```json\n#{canned}\n```"} end
    ctx = %ProjectContext{path: System.tmp_dir!(), type: :feature, task: "x"}

    {:ok, %PreCheck{verdict: :revise, notes: notes, suggested_changes: changes}} =
      PreChecker.run(@plan, project_context: ctx, llm_client: stub(mock))

    assert notes == ["lib/foo.ex já é grande demais"]
    assert changes == ["Split foo.ex first"]
  end

  defp stub(fun) do
    # Same pattern as Planner test; extract to a shared TestSupport module
    # if the codebase has one (check test/support/).
    mod = Module.concat([:Stub, :crypto.strong_rand_bytes(8) |> Base.encode16()])
    Code.eval_string("""
    defmodule #{inspect(mod)} do
      def complete(m, msgs, opts), do: (#{inspect(fun)}).(m, msgs, opts)
      def stream(m, msgs, opts, _h), do: complete(m, msgs, opts)
    end
    """)
    mod
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `docker compose run --rm trivium mix test test/trivium/build/agents/pre_checker_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 3: Implement the PreChecker**

```elixir
defmodule Trivium.Build.Agents.PreChecker do
  @moduledoc """
  Reads existing code mentioned in the plan and validates the plan against it.
  Output verdict :ok or :revise, with notes and suggested plan edits.
  """

  alias Trivium.Config
  alias Trivium.Build.Types.{Plan, PreCheck}
  alias Trivium.Types.ProjectContext

  @system_prompt """
  Você é um revisor pré-implementação. Receba (1) um plano de steps e (2)
  acesso read-only ao código do projeto via Read/Grep/Glob. Sua função:

  - Ler os arquivos que o plano vai tocar.
  - Detectar conflitos: mudanças que quebram código existente, padrões
    ignorados, redundância (algo similar já existe).
  - Sugerir edits ao plano (não reescreva o plano — só sugira).

  Verdicts:
  - "ok" se o plano está alinhado com o código existente e é seguro executar.
  - "revise" se há conflitos ou sugestões importantes.

  Formato OBRIGATÓRIO no fim — JSON puro:

  ```json
  {"verdict": "ok|revise", "notes": ["..."], "suggested_changes": ["..."]}
  ```
  """

  def run(%Plan{} = plan, opts) do
    client = Keyword.get(opts, :llm_client, Config.llm_client())
    project_context = Keyword.fetch!(opts, :project_context)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: render_plan_for_review(plan)}
    ]

    model = Config.model_for(:technical_researcher)

    llm_opts = [
      role: :pre_checker,
      add_dir: project_context.path,
      allowed_tools: "Read Grep Glob"
    ]

    with {:ok, text} <- client.complete(model, messages, llm_opts),
         {:ok, json} <- find_json(text),
         {:ok, %{"verdict" => v} = parsed} <- Jason.decode(json),
         {:ok, verdict} <- parse_verdict(v) do
      {:ok,
       %PreCheck{
         verdict: verdict,
         notes: parsed["notes"] || [],
         suggested_changes: parsed["suggested_changes"] || []
       }}
    else
      {:error, _} = e -> e
      :error -> {:error, :no_json_in_pre_checker_output}
      {:ok, other} -> {:error, {:pre_check_missing_fields, other}}
      err -> {:error, err}
    end
  end

  defp render_plan_for_review(%Plan{} = p) do
    steps =
      p.steps
      |> Enum.map_join("\n", fn s ->
        "#{s.index}. #{s.title}\n   files: #{Enum.join(s.files, ", ")}\n   accept: #{s.acceptance}"
      end)

    """
    Plano a revisar:

    Tópico: #{p.topic}

    Steps:
    #{steps}
    """
  end

  defp find_json(text) do
    case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
      [_, json] -> {:ok, json}
      _ -> :error
    end
  end

  defp parse_verdict("ok"), do: {:ok, :ok}
  defp parse_verdict("revise"), do: {:ok, :revise}
  defp parse_verdict(other), do: {:error, {:invalid_verdict, other}}
end
```

- [ ] **Step 4: Run tests**

Run: `docker compose run --rm trivium mix test test/trivium/build/agents/pre_checker_test.exs`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/trivium/build/agents/pre_checker.ex test/trivium/build/agents/pre_checker_test.exs
git commit -m "feat(build): PreChecker agent — validate plan vs existing code"
```

---

### Task 5: `Reviewer` agent

**Files:**
- Create: `lib/trivium/build/agents/reviewer.ex`
- Create: `test/trivium/build/agents/reviewer_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Trivium.Build.Agents.ReviewerTest do
  use ExUnit.Case, async: true

  alias Trivium.Build.Agents.Reviewer
  alias Trivium.Build.Types.{Plan, Step, Review}

  @plan %Plan{
    topic: "Add X",
    base_ref: "abc",
    status: :review_pending,
    created_at: DateTime.utc_now(),
    steps: [%Step{index: 1, title: "Touch foo", files: ["lib/foo.ex"], acceptance: "compiles", done?: true}]
  }

  @diff """
  diff --git a/lib/foo.ex b/lib/foo.ex
  +defmodule Foo do
  +  def bar, do: :ok
  +end
  """

  test "approved verdict" do
    canned = ~s({"verdict": "approved", "findings": [], "improvements": []})
    mock = fn _, _, _ -> {:ok, "```json\n#{canned}\n```"} end

    {:ok, %Review{verdict: :approved}} = Reviewer.run(@plan, @diff, llm_client: stub(mock))
  end

  test "needs_work verdict surfaces findings" do
    canned = ~s({"verdict": "needs_work", "findings": ["foo.bar/0 has no doc"], "improvements": ["add @doc"]})
    mock = fn _, _, _ -> {:ok, "```json\n#{canned}\n```"} end

    {:ok, %Review{verdict: :needs_work, findings: ["foo.bar/0 has no doc"], improvements: ["add @doc"]}} =
      Reviewer.run(@plan, @diff, llm_client: stub(mock))
  end

  defp stub(fun), do: Trivium.Build.Agents.PreCheckerTest.__info__(:functions) && raise "use shared stub"
  # ↑ replace by extracting Trivium.Build.Agents.PreCheckerTest.stub/1 into a
  #   shared `test/support/llm_stub.ex` helper before/while writing this test.
end
```

> **Test infra refactor required at this point:** the same stub-client pattern appears in 3 tests (Planner, PreChecker, Reviewer). Before writing this third test, extract a single helper at `test/support/llm_stub.ex`:
>
> ```elixir
> defmodule Trivium.Test.LLMStub do
>   def with(complete_fun) do
>     mod = Module.concat([:LLMStub, :crypto.strong_rand_bytes(8) |> Base.encode16()])
>     Code.eval_string("""
>     defmodule #{inspect(mod)} do
>       def complete(m, msgs, opts), do: (#{inspect(complete_fun)}).(m, msgs, opts)
>       def stream(m, msgs, opts, _h), do: complete(m, msgs, opts)
>     end
>     """)
>     mod
>   end
> end
> ```
>
> Add `elixirc_paths: elixirc_paths(Mix.env())` to `mix.exs` if not present, with `defp elixirc_paths(:test), do: ["lib", "test/support"]; defp elixirc_paths(_), do: ["lib"]`. Update Tasks 3 & 4 tests to use `Trivium.Test.LLMStub.with/1` after extracting it.

- [ ] **Step 2: Run the test to verify it fails**

Run: `docker compose run --rm trivium mix test test/trivium/build/agents/reviewer_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 3: Implement the Reviewer**

```elixir
defmodule Trivium.Build.Agents.Reviewer do
  @moduledoc """
  Validates a code diff against the plan that produced it.
  """

  alias Trivium.Config
  alias Trivium.Build.Types.{Plan, Review}

  @system_prompt """
  Você é um code reviewer. Recebe (1) um plano com steps + critérios de aceite
  e (2) um diff git. Sua função:

  - Verificar se o diff entrega o que cada step prometeu (acceptance bate?).
  - Verificar se regras de negócio existentes foram preservadas.
  - Sugerir melhorias específicas (não genéricas como "adicione testes").

  Verdicts:
  - "approved" se o diff entrega o plano sem regredir nada.
  - "needs_work" se faltou algo, escopo diverge, ou há regressão.

  Formato OBRIGATÓRIO no fim — JSON puro:

  ```json
  {"verdict": "approved|needs_work", "findings": ["..."], "improvements": ["..."]}
  ```
  """

  def run(%Plan{} = plan, diff, opts) when is_binary(diff) do
    client = Keyword.get(opts, :llm_client, Config.llm_client())

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: render(plan, diff)}
    ]

    model = Config.model_for(:qa)
    llm_opts = [role: :reviewer]

    with {:ok, text} <- client.complete(model, messages, llm_opts),
         {:ok, json} <- find_json(text),
         {:ok, %{"verdict" => v} = parsed} <- Jason.decode(json),
         {:ok, verdict} <- parse_verdict(v) do
      {:ok,
       %Review{
         verdict: verdict,
         findings: parsed["findings"] || [],
         improvements: parsed["improvements"] || []
       }}
    else
      {:error, _} = e -> e
      :error -> {:error, :no_json_in_reviewer_output}
      {:ok, other} -> {:error, {:review_missing_fields, other}}
      err -> {:error, err}
    end
  end

  defp render(%Plan{} = p, diff) do
    steps =
      p.steps
      |> Enum.map_join("\n", fn s ->
        "#{s.index}. #{s.title} — accept: #{s.acceptance} — done?: #{s.done?}"
      end)

    """
    Plano:

    Tópico: #{p.topic}

    Steps:
    #{steps}

    Diff a revisar:

    ```diff
    #{diff}
    ```
    """
  end

  defp find_json(text) do
    case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
      [_, json] -> {:ok, json}
      _ -> :error
    end
  end

  defp parse_verdict("approved"), do: {:ok, :approved}
  defp parse_verdict("needs_work"), do: {:ok, :needs_work}
  defp parse_verdict(other), do: {:error, {:invalid_verdict, other}}
end
```

- [ ] **Step 4: Run tests**

Run: `docker compose run --rm trivium mix test test/trivium/build/agents/reviewer_test.exs`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/trivium/build/agents/reviewer.ex test/trivium/build/agents/reviewer_test.exs test/support/llm_stub.ex mix.exs
git commit -m "feat(build): Reviewer agent + shared LLM stub helper"
```

---

### Task 6: `BuildOrchestrator`

**Files:**
- Create: `lib/trivium/build/orchestrator.ex`
- Create: `test/trivium/build/orchestrator_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Trivium.Build.OrchestratorTest do
  use ExUnit.Case, async: true

  alias Trivium.Build.Orchestrator
  alias Trivium.Build.PlanIO
  alias Trivium.Test.LLMStub
  alias Trivium.Types.ProjectContext

  @planner_response """
  ```json
  {"topic": "Add X", "steps": [
    {"title": "Add module", "files": ["lib/x.ex"], "acceptance": "compiles"}
  ]}
  ```
  """

  @pre_check_response """
  ```json
  {"verdict": "ok", "notes": [], "suggested_changes": []}
  ```
  """

  test "build/2 writes a plan file and returns its path" do
    tmp = System.tmp_dir!() |> Path.join("trivium-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "docs/trivium"))

    # Create a fake git base_ref by initialising a repo.
    {_, 0} = System.cmd("git", ["init"], cd: tmp)
    File.write!(Path.join(tmp, "README.md"), "x")
    {_, 0} = System.cmd("git", ["-C", tmp, "add", "."])
    {_, 0} = System.cmd("git", ["-C", tmp, "commit", "-m", "init", "-c", "user.email=t@t", "-c", "user.name=t"])

    ctx = %ProjectContext{path: tmp, type: :feature, task: "Add X"}

    client =
      LLMStub.with(fn _model, msgs, opts ->
        case Keyword.get(opts, :role) do
          :planner -> {:ok, @planner_response}
          :pre_checker -> {:ok, @pre_check_response}
          other -> raise "unexpected role #{inspect(other)} (msgs=#{inspect(msgs)})"
        end
      end)

    {:ok, path} = Orchestrator.build("spec text here", project_context: ctx, llm_client: client)

    assert File.exists?(path)
    {:ok, plan} = path |> File.read!() |> PlanIO.decode()

    assert plan.topic == "Add X"
    assert plan.status == :draft
    assert byte_size(plan.base_ref) >= 7
    assert length(plan.steps) == 1

    File.rm_rf!(tmp)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `docker compose run --rm trivium mix test test/trivium/build/orchestrator_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 3: Implement `BuildOrchestrator`**

```elixir
defmodule Trivium.Build.Orchestrator do
  @moduledoc """
  Sequential pipeline: Planner -> PreChecker -> write plan file.
  """

  alias Trivium.Build.{PlanIO, Types}
  alias Trivium.Build.Agents.{Planner, PreChecker}
  alias Trivium.Build.Types.Plan
  alias Trivium.Types.ProjectContext

  @spec build(String.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def build(spec, opts) do
    %ProjectContext{path: project_path} = ctx = Keyword.fetch!(opts, :project_context)

    with {:ok, base_ref} <- current_head(project_path),
         {:ok, plan} <-
           Planner.run(spec,
             base_ref: base_ref,
             llm_client: opts[:llm_client],
             project_context: ctx
           ),
         {:ok, %Types.PreCheck{} = pc} <-
           PreChecker.run(plan,
             project_context: ctx,
             llm_client: opts[:llm_client]
           ),
         plan = merge_pre_check(plan, pc, spec),
         {:ok, path} <- write_plan(project_path, plan) do
      {:ok, path}
    end
  end

  defp current_head(repo_path) do
    case System.cmd("git", ["-C", repo_path, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> {:ok, String.trim(sha)}
      {err, _} -> {:error, {:no_base_ref, String.trim(err)}}
    end
  end

  defp merge_pre_check(%Plan{} = plan, pc, spec) do
    notes =
      case {pc.notes, pc.suggested_changes} do
        {[], []} -> "No conflicts found."
        {n, sc} -> Enum.map_join(n ++ sc, "\n", &"- #{&1}")
      end

    %{plan | pre_check_notes: notes, context: String.slice(spec, 0, 400)}
  end

  defp write_plan(project_path, %Plan{} = plan) do
    dir = Path.join(project_path, "docs/trivium")
    File.mkdir_p!(dir)
    date = plan.created_at |> DateTime.to_date() |> Date.to_iso8601()
    slug = plan.topic |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
    path = Path.join(dir, "#{date}-#{slug}-plan.md")
    File.write!(path, PlanIO.encode(plan))
    {:ok, path}
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `docker compose run --rm trivium mix test test/trivium/build/orchestrator_test.exs`
Expected: 1 test, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/trivium/build/orchestrator.ex test/trivium/build/orchestrator_test.exs
git commit -m "feat(build): BuildOrchestrator — Planner+PreChecker -> plan file"
```

---

### Task 7: CLI `build` subcommand

**Files:**
- Modify: `lib/trivium/cli.ex` — convert from flat options to Optimus subcommand mode (default `evaluate` for current behaviour, plus `build`, `review`)

- [ ] **Step 1: Read the current `cli.ex`**

The existing CLI has no subcommands — `--path/--type/--task` triggers project mode, otherwise REPL. The new pipeline needs `trivium build` and `trivium review` as first-positional subcommands. Preserve the current behaviour as the default when no subcommand is given.

- [ ] **Step 2: Restructure `main/1` to dispatch on first arg**

Replace the body of `main/1` with:

```elixir
def main(argv) do
  {:ok, _} = Application.ensure_all_started(:trivium)

  case argv do
    ["build" | rest] -> run_build(rest)
    ["review" | rest] -> run_review(rest)
    _ -> run_legacy(argv)  # the current Optimus.parse! flow, unchanged
  end
end
```

Move all the current `main/1` body (Optimus, parse, REPL/one-shot dispatch) into a new private `run_legacy/1` function unchanged.

- [ ] **Step 3: Add `run_build/1`**

```elixir
defp run_build(rest) do
  optimus =
    Optimus.new!(
      name: "trivium build",
      description: "Generate plan + pre-check from a spec",
      allow_unknown_args: false,
      args: [
        spec: [
          value_name: "SPEC",
          help: "Path to a spec file, or '-' for stdin",
          required: true
        ]
      ],
      options: [
        path: [value_name: "DIR", long: "--path", help: "Project dir", required: true]
      ]
    )

  %{args: %{spec: spec_arg}, options: %{path: path}} = Optimus.parse!(optimus, rest)

  spec =
    case spec_arg do
      "-" -> IO.read(:stdio, :eof)
      file -> File.read!(file)
    end

  ctx = %Trivium.Types.ProjectContext{path: path, type: :feature, task: spec}

  case Trivium.Build.Orchestrator.build(spec, project_context: ctx) do
    {:ok, plan_path} ->
      IO.puts("TRIVIUM_PLAN_WRITTEN: #{plan_path}")
      System.halt(0)

    {:error, reason} ->
      IO.puts(:stderr, "build failed: #{inspect(reason)}")
      System.halt(1)
  end
end
```

- [ ] **Step 4: Smoke-test the build subcommand**

Run (from a scratch git repo):

```bash
docker compose run --rm trivium ./trivium build /tmp/sample-spec.md --path /tmp/sample-repo
```

Expected: with the real `claude` CLI available, prints `TRIVIUM_PLAN_WRITTEN: …` and creates the plan file. (If you don't have a sample, skip — Task 8 also exercises CLI surface.)

- [ ] **Step 5: Commit**

```bash
git add lib/trivium/cli.ex
git commit -m "feat(cli): add 'trivium build' subcommand"
```

---

### Task 8: CLI `review` subcommand

**Files:**
- Modify: `lib/trivium/cli.ex`

- [ ] **Step 1: Add `run_review/1`**

```elixir
defp run_review(rest) do
  optimus =
    Optimus.new!(
      name: "trivium review",
      description: "Review a diff against a plan",
      allow_unknown_args: false,
      args: [
        plan: [
          value_name: "PLAN_PATH",
          help: "Path to the plan file",
          required: true
        ]
      ],
      options: [
        path: [value_name: "DIR", long: "--path", help: "Project dir (defaults to plan's repo)", required: false]
      ]
    )

  %{args: %{plan: plan_path}, options: %{path: opt_path}} = Optimus.parse!(optimus, rest)

  with {:ok, md} <- File.read(plan_path),
       {:ok, plan} <- Trivium.Build.PlanIO.decode(md),
       repo_path = opt_path || infer_repo(plan_path),
       {:ok, diff} <- git_diff(repo_path, plan.base_ref),
       :nonempty <- nonempty(diff),
       {:ok, review} <- Trivium.Build.Agents.Reviewer.run(plan, diff, []),
       review_body = format_review(review),
       {:ok, updated} <- Trivium.Build.PlanIO.append_review(md, review_body),
       new_status = if(review.verdict == :approved, do: :approved, else: :needs_work),
       {:ok, with_status} <- Trivium.Build.PlanIO.set_status(updated, new_status),
       :ok <- File.write(plan_path, with_status) do
    IO.puts(review_body)
    System.halt(if review.verdict == :approved, do: 0, else: 2)
  else
    :empty ->
      IO.puts(:stderr, "nothing to review (diff is empty)")
      System.halt(0)

    {:error, reason} ->
      IO.puts(:stderr, "review failed: #{inspect(reason)}")
      System.halt(1)
  end
end

defp git_diff(repo, base_ref) do
  case System.cmd("git", ["-C", repo, "diff", "#{base_ref}..HEAD"], stderr_to_stdout: true) do
    {out, 0} -> {:ok, out}
    {err, _} -> {:error, {:git_diff_failed, String.trim(err)}}
  end
end

defp nonempty(diff) when byte_size(diff) > 0, do: :nonempty
defp nonempty(_), do: :empty

defp infer_repo(plan_path), do: plan_path |> Path.dirname() |> Path.dirname() |> Path.dirname()

defp format_review(%Trivium.Build.Types.Review{} = r) do
  findings = if r.findings == [], do: "none", else: Enum.map_join(r.findings, "\n", &"- #{&1}")
  improvements = if r.improvements == [], do: "none", else: Enum.map_join(r.improvements, "\n", &"- #{&1}")

  """
  Verdict: #{r.verdict}

  Findings:
  #{findings}

  Improvements:
  #{improvements}
  """
end
```

- [ ] **Step 2: Compile**

Run: `docker compose run --rm trivium mix compile`
Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add lib/trivium/cli.ex
git commit -m "feat(cli): add 'trivium review' subcommand"
```

---

### Task 9: Slash command `/trivium-build`

**Files:**
- Create: `commands/trivium-build.md`

- [ ] **Step 1: Write the file**

```markdown
---
description: Generate a development plan + pre-check from an approved spec, optionally execute it
argument-hint: "<spec text or path-to-spec.md>"
---

The user wants to turn a spec into a structured plan. The spec input is in `$ARGUMENTS`.

Steps:

1. Confirm Docker is running: `docker ps`. If it fails, tell the user to start Docker and stop.

2. Resolve the spec input:
   - If `$ARGUMENTS` is a path that exists, use it as-is.
   - Otherwise, write `$ARGUMENTS` to a temp file at `/tmp/trivium-spec-$$.md` and use that path.

3. Run:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/trivium build <spec-path> --path "$PWD"
```

4. Parse the output. The last line should be `TRIVIUM_PLAN_WRITTEN: <path>`.
   - If you see that marker: read the plan file, summarise the steps for the user (numbered list, one line each), and **show the pre-check notes** prominently if they are anything other than "No conflicts found.".
   - If the pre-check flagged revisions, ask the user: "Pre-check suggested revisions — do you want to revise the plan first, or proceed?" Wait for the answer.
   - Otherwise, proceed to step 5.

5. **Ask the user:** "Quer que eu execute esse plano agora?" Wait for the answer.
   - If yes: follow the instructions in `commands/trivium-execute.md` using the plan path as input.
   - If no: tell the user "OK — when you're ready, run `/trivium-execute <plan-path>`" and stop.

6. If the bash command failed (no `TRIVIUM_PLAN_WRITTEN:` marker), surface the stderr and stop.
```

- [ ] **Step 2: Commit**

```bash
git add commands/trivium-build.md
git commit -m "feat(plugin): /trivium-build slash command"
```

---

### Task 10: Slash command `/trivium-execute`

**Files:**
- Create: `commands/trivium-execute.md`

- [ ] **Step 1: Write the file**

```markdown
---
description: Execute a Trivium plan step by step, then auto-trigger review
argument-hint: "<path-to-plan.md>"
---

The user wants to execute a Trivium plan. The plan path is in `$ARGUMENTS`.

Steps:

1. Read the plan file at `$ARGUMENTS` with the Read tool.

2. Check the front-matter `status:` field:
   - `draft` or `in_progress`: proceed.
   - `approved`: ask "This plan is already approved. Re-execute?" — only proceed on yes.
   - `review_pending` or `needs_work`: warn the user and ask whether to re-execute.

3. Update the front-matter to `status: in_progress` using the Edit tool (replace the line `status: <whatever>` with `status: in_progress`).

4. Convert the unchecked steps (lines starting `- [ ] **N.`) into TODOs with TaskCreate, one TODO per step, using the step title as the TODO content.

5. For each step in order:
   a. Mark the TODO as `in_progress`.
   b. Implement the step — read the listed `**Files**`, write code, run any tests implied by `**Acceptance**`.
   c. When the step's acceptance criterion is met, mark the checkbox `[x]` in the plan file (Edit: change `- [ ] **N.` to `- [x] **N.`).
   d. Mark the TODO as `completed`.
   e. If a step fails: append a `**Failure note:**` line below the step in the plan file, set front-matter `status: needs_work`, leave the checkbox `[ ]`, do NOT proceed to the review, and report to the user.

6. After all steps are `[x]`:
   a. Update front-matter `status: review_pending`.
   b. Run `/trivium-review $ARGUMENTS` by following the instructions in `commands/trivium-review.md`.

7. Surface the review verdict to the user.
```

- [ ] **Step 2: Commit**

```bash
git add commands/trivium-execute.md
git commit -m "feat(plugin): /trivium-execute slash command"
```

---

### Task 11: Slash command `/trivium-review`

**Files:**
- Create: `commands/trivium-review.md`

- [ ] **Step 1: Write the file**

```markdown
---
description: Review the diff against a Trivium plan and append findings to the plan file
argument-hint: "<path-to-plan.md>"
---

The user wants Trivium to review the implementation against a plan. The plan path is in `$ARGUMENTS`.

Steps:

1. Confirm Docker is running: `docker ps`. If it fails, tell the user to start Docker and stop.

2. Run:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/trivium review "$ARGUMENTS"
```

3. Surface the output:
   - Exit code 0 → verdict `approved`. Show the verdict block + tell the user the plan file's `## Review` section was updated.
   - Exit code 2 → verdict `needs_work`. Show findings + improvements; remind the user the plan status is now `needs_work` and they can re-run the review after fixes (which will append `## Review (2)`).
   - Exit code 1 → error. Surface stderr.
```

- [ ] **Step 2: Commit**

```bash
git add commands/trivium-review.md
git commit -m "feat(plugin): /trivium-review slash command"
```

---

### Task 12: Bump plugin version + update README

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `README.md`

- [ ] **Step 1: Bump version in `plugin.json`**

Edit the `"version"` field from `"0.1.0"` to `"0.2.0"`.

- [ ] **Step 2: Update README — Commands section**

Add three entries to the Commands section (find the existing `### Commands` heading), documenting `/trivium-build`, `/trivium-execute`, `/trivium-review` with the same style as the existing `/trivium-feature` etc.

Add a new subsection `### Pipeline mode (build → execute → review)` after the existing commands list, with a 3-5 line summary of the flow and a note that the plan file lives at `docs/trivium/<date>-<slug>-plan.md` in the target project.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json README.md
git commit -m "docs: document /trivium-build /trivium-execute /trivium-review pipeline"
```

---

### Task 13: End-to-end smoke test (manual)

**Not a code task.** Verifies the full pipeline against a real Claude CLI.

- [ ] **Step 1: Re-install the plugin from the local marketplace**

```
/plugin marketplace remove trivium
/plugin marketplace add /home/yuhigawa/ws/personal/Trivium
/plugin install trivium@trivium
```

- [ ] **Step 2: From a scratch test repo, run a tiny build**

```bash
mkdir /tmp/trivium-smoke && cd /tmp/trivium-smoke && git init && echo x > a && git add a && git commit -m init
```

In Claude Code session inside `/tmp/trivium-smoke`:

```
/trivium-build add a hello() function to a new module Greeter that returns "hello"
```

- [ ] **Step 3: Verify the plan file**

Open `/tmp/trivium-smoke/docs/trivium/<date>-<slug>-plan.md`. Check:
- Front-matter has `topic`, `base_ref` (real SHA), `status: draft`, `created`.
- At least one step with title, files, acceptance.
- `## Pre-check notes` section is non-empty.

- [ ] **Step 4: Accept the "execute now?" prompt**

Confirm Claude implements step by step, ticks `[x]`, and the plan ends with `status: approved` (or `needs_work` if review flagged something).

- [ ] **Step 5: Re-run review on a deliberate regression**

Manually break the implemented function in `/tmp/trivium-smoke`, then:

```
/trivium-review docs/trivium/<plan-file>.md
```

Expected: verdict `needs_work`, `## Review (2)` appended.

If anything fails, file an issue and iterate. Do not commit changes from the smoke test.

---

## Self-review

**Spec coverage check** — every spec section maps to at least one task:

- "End-to-end flow" → Tasks 6, 7, 8, 9, 10, 11
- "New Elixir modules" → Tasks 2 (PlanIO), 3 (Planner), 4 (PreChecker), 5 (Reviewer), 6 (Orchestrator)
- "New types in types.ex" → Task 1 (note: under `Trivium.Build.Types` namespace, not modifying the existing `Trivium.Types`)
- "CLI additions" → Tasks 7, 8
- "Three new slash commands" → Tasks 9, 10, 11
- "Plan artefact format" → Task 2 (encode/decode tests assert the exact format)
- "Handoff mechanics" → Task 9 (TRIVIUM_PLAN_WRITTEN marker), Task 10 (status transitions), Task 7 (CLI emits the marker)
- "Error handling — `/trivium-build` PreChecker `:revise`" → Task 9 step 4
- "Error handling — `/trivium-execute` step failure" → Task 10 step 5e
- "Error handling — `/trivium-review` empty diff" → Task 8 (`:empty` branch)
- "Testing strategy" → tests in Tasks 2, 3, 4, 5, 6 + manual Task 13

**Type consistency check:**
- `Plan.status` atoms: `:draft | :in_progress | :review_pending | :approved | :needs_work` — used consistently in PlanIO, Orchestrator, CLI, slash commands.
- `PreCheck.verdict`: `:ok | :revise` — consistent.
- `Review.verdict`: `:approved | :needs_work` — consistent.
- The new `Trivium.Build.Types.Review` is intentionally distinct from `Trivium.Types.Review` (gate review with `:role`/`:score`); always use full module path or alias.

**Placeholder scan:** No "TBD"/"TODO". Every code step has full code. The Reviewer test (Task 5) explicitly notes the test infra refactor before that test runs and gives the exact code for the shared helper.

**Mix.exs change for test/support:** Task 5 notes the requirement to add `elixirc_paths` to `mix.exs`. The committer for Task 5 should include the `mix.exs` change.

---

## Execution handoff

Plan complete and saved to `docs/2026-04-21-plan-build-review-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
