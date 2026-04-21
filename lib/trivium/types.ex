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
    defstruct [:status, :attempts, :final_idea, :final_reviews, :project_context]

    @type status :: :approved | :rejected | :error
    @type t :: %__MODULE__{
            status: status(),
            attempts: [Trivium.Types.Attempt.t()],
            final_idea: Trivium.Types.Idea.t() | nil,
            final_reviews: [Trivium.Types.Review.t()] | nil,
            project_context: Trivium.Types.ProjectContext.t() | nil
          }
  end

  defmodule ProjectContext do
    @enforce_keys [:path, :type, :task]
    defstruct [:path, :type, :task]

    @valid_types [:bug_fix, :feature, :analysis]

    @type task_type :: :bug_fix | :feature | :analysis
    @type t :: %__MODULE__{
            path: String.t(),
            type: task_type(),
            task: String.t()
          }

    def valid_types, do: @valid_types

    def validate(%__MODULE__{} = ctx) do
      cond do
        ctx.type not in @valid_types -> {:error, {:invalid_type, ctx.type}}
        not is_binary(ctx.path) or not File.dir?(ctx.path) -> {:error, {:invalid_path, ctx.path}}
        not is_binary(ctx.task) or String.trim(ctx.task) == "" -> {:error, :empty_task}
        true -> {:ok, ctx}
      end
    end
  end
end
