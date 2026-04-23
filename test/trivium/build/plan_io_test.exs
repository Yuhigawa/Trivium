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

  test "set_status is a no-op (still :ok) when target equals current status" do
    md = PlanIO.encode(%{@sample | status: :needs_work})
    assert {:ok, ^md} = PlanIO.set_status(md, :needs_work)
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
