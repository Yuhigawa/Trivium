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
      trivium_version: "0.1.0",
      auto_execute: false
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
            trivium_version: String.t(),
            auto_execute: boolean()
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
