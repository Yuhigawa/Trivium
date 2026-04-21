defmodule Trivium.Types do
  @moduledoc "Structs do domínio — contratos explícitos entre Orchestrator e agentes."

  defmodule Idea do
    @enforce_keys [:content]
    defstruct [:content]
    @type t :: %__MODULE__{content: String.t()}
  end

  defmodule Review do
    @enforce_keys [:role, :score, :justification]
    defstruct [:role, :score, :justification]

    @type t :: %__MODULE__{
            role: :idea_writer | :technical_researcher | :qa,
            score: integer(),
            justification: String.t()
          }
  end

  defmodule Attempt do
    @enforce_keys [:n, :idea, :reviews]
    defstruct [:n, :idea, :reviews]

    @type t :: %__MODULE__{
            n: pos_integer(),
            idea: Trivium.Types.Idea.t(),
            reviews: [Trivium.Types.Review.t()]
          }
  end

  defmodule Result do
    @enforce_keys [:status, :attempts]
    defstruct [:status, :attempts, :final_idea, :final_reviews]

    @type status :: :approved | :rejected | :error
    @type t :: %__MODULE__{
            status: status(),
            attempts: [Trivium.Types.Attempt.t()],
            final_idea: Trivium.Types.Idea.t() | nil,
            final_reviews: [Trivium.Types.Review.t()] | nil
          }
  end
end
