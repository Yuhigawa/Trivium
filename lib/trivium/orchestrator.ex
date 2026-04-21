defmodule Trivium.Orchestrator do
  @moduledoc """
  Coordena uma sessão de avaliação.

  Fluxo por tentativa:
  1. `IdeaWriter.run/2` (sozinho) → `%Idea{}`
  2. Em paralelo (3 Tasks): `IdeaWriter.self_review/1`, `TechnicalResearcher.run/1`, `QA.run/1`
  3. Se todas reviews > threshold → :approved.
     Senão e n < max → próxima tentativa passando só as reviews REPROVADAS.
     Senão → :rejected.

  Isolamento garantido: cada agente roda em `Task.async` separado e recebe só
  o que precisa. Orchestrator é o único que vê todos os outputs.

  Quando recebe `:project_context` nas opts, propaga aos 4 agentes e carrega
  no Result final (para o Report exibir header).
  """

  alias Trivium.{Config, Events}
  alias Trivium.Agents.{IdeaWriter, TechnicalResearcher, QA}
  alias Trivium.Types.{Attempt, ProjectContext, Result}

  @type opts :: [
          session_id: term(),
          max_attempts: pos_integer(),
          threshold: integer(),
          llm_client: module(),
          stream: boolean(),
          project_context: ProjectContext.t() | nil
        ]

  @spec evaluate(String.t(), opts()) :: Result.t()
  def evaluate(task, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, make_ref())
    max_attempts = Keyword.get(opts, :max_attempts, Config.max_attempts())
    threshold = Keyword.get(opts, :threshold, Config.approval_threshold())
    llm_client = Keyword.get(opts, :llm_client, Config.llm_client())
    stream? = Keyword.get(opts, :stream, false)
    project_context = Keyword.get(opts, :project_context)

    Events.publish(session_id, :session_started)

    attempts =
      Enum.reduce_while(1..max_attempts, [], fn n, acc ->
        Events.publish(session_id, {:attempt_started, n, max_attempts})
        previous = Enum.reverse(acc)

        case run_attempt(n, task, previous, session_id, llm_client, stream?, project_context) do
          {:ok, %Attempt{} = attempt} ->
            if all_pass?(attempt.reviews, threshold) do
              Events.publish(session_id, {:scores_computed, attempt.reviews, :pass})
              {:halt, [attempt | acc]}
            else
              Events.publish(session_id, {:scores_computed, attempt.reviews, :fail})
              {:cont, [attempt | acc]}
            end

          {:error, reason} ->
            result = %Result{
              status: :error,
              attempts: Enum.reverse(acc),
              final_idea: nil,
              final_reviews: nil,
              project_context: project_context
            }

            Events.publish(session_id, {:agent_error, :orchestrator, reason})
            Events.publish(session_id, {:session_finished, result})
            {:halt, {:error, reason, acc}}
        end
      end)

    build_result(attempts, threshold, session_id, project_context)
  end

  defp run_attempt(n, task, previous_attempts, session_id, llm_client, stream?, project_context) do
    chunk = chunk_handler(session_id)

    Events.publish(session_id, {:agent_started, :idea_writer})

    case IdeaWriter.run(task, previous_attempts,
           llm_client: llm_client,
           stream: stream?,
           chunk_handler: chunk.(:idea_writer),
           project_context: project_context
         ) do
      {:ok, idea} ->
        Events.publish(session_id, {:agent_finished, :idea_writer, :idea, idea})

        reviews =
          run_reviews_in_parallel(idea, session_id, llm_client, stream?, chunk, project_context)

        {:ok, %Attempt{n: n, idea: idea, reviews: reviews}}

      {:error, reason} ->
        Events.publish(session_id, {:agent_error, :idea_writer, reason})
        {:error, reason}
    end
  end

  defp run_reviews_in_parallel(idea, session_id, llm_client, stream?, chunk, project_context) do
    [
      Task.Supervisor.async(Trivium.AgentTasks, fn ->
        Events.publish(session_id, {:agent_started, :idea_writer})

        case IdeaWriter.self_review(idea,
               llm_client: llm_client,
               stream: stream?,
               chunk_handler: chunk.(:idea_writer)
             ) do
          {:ok, review} ->
            Events.publish(session_id, {:agent_finished, :idea_writer, :review, review})
            review

          {:error, reason} ->
            Events.publish(session_id, {:agent_error, :idea_writer, reason})
            nil
        end
      end),
      Task.Supervisor.async(Trivium.AgentTasks, fn ->
        Events.publish(session_id, {:agent_started, :technical_researcher})

        case TechnicalResearcher.run(idea,
               llm_client: llm_client,
               stream: stream?,
               chunk_handler: chunk.(:technical_researcher),
               project_context: project_context
             ) do
          {:ok, review} ->
            Events.publish(session_id, {:agent_finished, :technical_researcher, :review, review})
            review

          {:error, reason} ->
            Events.publish(session_id, {:agent_error, :technical_researcher, reason})
            nil
        end
      end),
      Task.Supervisor.async(Trivium.AgentTasks, fn ->
        Events.publish(session_id, {:agent_started, :qa})

        case QA.run(idea,
               llm_client: llm_client,
               stream: stream?,
               chunk_handler: chunk.(:qa),
               project_context: project_context
             ) do
          {:ok, review} ->
            Events.publish(session_id, {:agent_finished, :qa, :review, review})
            review

          {:error, reason} ->
            Events.publish(session_id, {:agent_error, :qa, reason})
            nil
        end
      end)
    ]
    |> Task.await_many(180_000)
    |> Enum.reject(&is_nil/1)
  end

  defp chunk_handler(session_id) do
    fn role ->
      fn chunk -> Events.publish(session_id, {:agent_token, role, chunk}) end
    end
  end

  defp all_pass?(reviews, threshold) do
    length(reviews) == 3 and Enum.all?(reviews, &(&1.score > threshold))
  end

  defp build_result({:error, reason, acc}, _threshold, _session_id, project_context) do
    %Result{
      status: :error,
      attempts: Enum.reverse(acc),
      final_idea: nil,
      final_reviews: [
        %Trivium.Types.Review{role: :idea_writer, score: 0, justification: inspect(reason)}
      ],
      project_context: project_context
    }
  end

  defp build_result(attempts, threshold, session_id, project_context) when is_list(attempts) do
    ordered = Enum.reverse(attempts)
    last = List.last(ordered)

    status =
      cond do
        last == nil -> :error
        all_pass?(last.reviews, threshold) -> :approved
        true -> :rejected
      end

    result = %Result{
      status: status,
      attempts: ordered,
      final_idea: last && last.idea,
      final_reviews: last && last.reviews,
      project_context: project_context
    }

    Events.publish(session_id, {:session_finished, result})
    result
  end
end
