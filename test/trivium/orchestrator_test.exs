defmodule Trivium.OrchestratorTest do
  use ExUnit.Case, async: false

  alias Trivium.LLM.Mock
  alias Trivium.Orchestrator
  alias Trivium.Types.Result

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  describe "evaluate/2 — caminho feliz" do
    test "aprova quando todos os 3 agentes dão score >= threshold" do
      idea_md = """
      ## Problema
      X

      ## Solução
      Y
      """

      Mock.set_script(:idea_writer, [idea_md])
      Mock.set_script(:idea_writer_review, [~s({"score": 9, "justification": "ok"})])

      Mock.set_script(:technical_researcher, [
        ~s({"score": 8, "justification": "viável"})
      ])

      Mock.set_script(:qa, [~s({"score": 8, "justification": "testável"})])

      result =
        Orchestrator.evaluate("criar X",
          llm_client: Mock,
          max_attempts: 3,
          threshold: 7
        )

      assert %Result{status: :approved, final_reviews: reviews, attempts: attempts} = result
      assert length(reviews) == 3
      assert length(attempts) == 1
      assert Enum.all?(reviews, &(&1.score > 7))
    end

    test "aprova quando o score é exatamente igual ao threshold (>= 7)" do
      Mock.set_script(:idea_writer, ["ideia"])
      Mock.set_script(:idea_writer_review, [~s({"score": 7, "justification": "exato"})])
      Mock.set_script(:technical_researcher, [~s({"score": 7, "justification": "exato"})])
      Mock.set_script(:qa, [~s({"score": 7, "justification": "exato"})])

      result = Orchestrator.evaluate("X", llm_client: Mock, max_attempts: 1, threshold: 7)

      assert %Result{status: :approved, final_reviews: reviews} = result
      assert Enum.all?(reviews, &(&1.score == 7))
    end
  end

  describe "evaluate/2 — loop de refinamento" do
    test "reprova primeira, aprova segunda" do
      Mock.set_script(:idea_writer, ["ideia v1", "ideia v2 refinada"])

      Mock.set_script(:idea_writer_review, [
        ~s({"score": 9, "justification": "ok v1"}),
        ~s({"score": 9, "justification": "ok v2"})
      ])

      Mock.set_script(:technical_researcher, [
        ~s({"score": 4, "justification": "raso v1"}),
        ~s({"score": 9, "justification": "agora ok"})
      ])

      Mock.set_script(:qa, [
        ~s({"score": 8, "justification": "ok v1"}),
        ~s({"score": 9, "justification": "ok v2"})
      ])

      result = Orchestrator.evaluate("tarefa X", llm_client: Mock, max_attempts: 3, threshold: 7)
      assert result.status == :approved
      assert length(result.attempts) == 2
    end

    test "esgota tentativas e reprova" do
      Mock.set_script(:idea_writer, ["v1", "v2", "v3"])

      Mock.set_script(:idea_writer_review, [
        ~s({"score": 3, "justification": "x"}),
        ~s({"score": 3, "justification": "x"}),
        ~s({"score": 3, "justification": "x"})
      ])

      Mock.set_script(:technical_researcher, [
        ~s({"score": 3, "justification": "x"}),
        ~s({"score": 3, "justification": "x"}),
        ~s({"score": 3, "justification": "x"})
      ])

      Mock.set_script(:qa, [
        ~s({"score": 3, "justification": "x"}),
        ~s({"score": 3, "justification": "x"}),
        ~s({"score": 3, "justification": "x"})
      ])

      result = Orchestrator.evaluate("tarefa", llm_client: Mock, max_attempts: 3, threshold: 7)
      assert result.status == :rejected
      assert length(result.attempts) == 3
    end
  end

  describe "project_context propagation" do
    test "todos os agentes recebem o mesmo project_context" do
      Mock.set_script(:idea_writer, ["idea"])
      Mock.set_script(:idea_writer_review, [~s({"score": 9, "justification": "ok"})])
      Mock.set_script(:technical_researcher, [~s({"score": 8, "justification": "ok"})])
      Mock.set_script(:qa, [~s({"score": 8, "justification": "ok"})])

      ctx = %Trivium.Types.ProjectContext{path: "/tmp", type: :bug_fix, task: "login bug"}

      Orchestrator.evaluate("login bug",
        llm_client: Mock,
        max_attempts: 1,
        threshold: 7,
        project_context: ctx
      )

      calls = Mock.calls()

      agent_calls =
        Enum.filter(calls, fn c ->
          c.opts[:role] in [:idea_writer, :technical_researcher, :qa]
        end)

      assert length(agent_calls) == 3

      Enum.each(agent_calls, fn c ->
        assert c.opts[:add_dir] == "/tmp",
               "role #{c.opts[:role]} não recebeu add_dir"

        assert c.opts[:allowed_tools] == "Read Grep Glob"
      end)
    end

    test "Result.project_context vem preenchido quando passado" do
      Mock.set_script(:idea_writer, ["idea"])
      Mock.set_script(:idea_writer_review, [~s({"score": 9, "justification": "ok"})])
      Mock.set_script(:technical_researcher, [~s({"score": 8, "justification": "ok"})])
      Mock.set_script(:qa, [~s({"score": 8, "justification": "ok"})])

      ctx = %Trivium.Types.ProjectContext{path: "/tmp", type: :feature, task: "x"}

      result =
        Orchestrator.evaluate("x",
          llm_client: Mock,
          max_attempts: 1,
          project_context: ctx
        )

      assert result.project_context == ctx
    end

    test "Result.project_context é nil quando não passado (backward-compat)" do
      Mock.set_script(:idea_writer, ["idea"])
      Mock.set_script(:idea_writer_review, [~s({"score": 9, "justification": "ok"})])
      Mock.set_script(:technical_researcher, [~s({"score": 8, "justification": "ok"})])
      Mock.set_script(:qa, [~s({"score": 8, "justification": "ok"})])

      result = Orchestrator.evaluate("x", llm_client: Mock, max_attempts: 1)

      assert result.project_context == nil
    end
  end

  describe "isolamento arquitetural" do
    test "QA e TechnicalResearcher NUNCA recebem output um do outro" do
      qa_sentinel = "QA_SENTINEL_#{System.unique_integer([:positive])}"
      tech_sentinel = "TECH_SENTINEL_#{System.unique_integer([:positive])}"

      Mock.set_script(:idea_writer, ["ideia limpa"])

      Mock.set_script(:idea_writer_review, [
        ~s({"score": 9, "justification": "ok"})
      ])

      Mock.set_script(:technical_researcher, [
        ~s({"score": 8, "justification": "#{tech_sentinel}"})
      ])

      Mock.set_script(:qa, [
        ~s({"score": 8, "justification": "#{qa_sentinel}"})
      ])

      Orchestrator.evaluate("tarefa", llm_client: Mock, max_attempts: 1, threshold: 7)

      calls = Mock.calls()

      tech_call = Enum.find(calls, &(&1.opts[:role] == :technical_researcher))
      qa_call = Enum.find(calls, &(&1.opts[:role] == :qa))

      assert tech_call, "tech call não registrada"
      assert qa_call, "qa call não registrada"

      tech_seen = tech_call.messages |> Enum.map_join("\n", & &1.content)
      qa_seen = qa_call.messages |> Enum.map_join("\n", & &1.content)

      refute tech_seen =~ qa_sentinel,
             "technical_researcher viu output do QA! ISOLAMENTO QUEBRADO"

      refute qa_seen =~ tech_sentinel,
             "qa viu output do technical_researcher! ISOLAMENTO QUEBRADO"
    end

    test "idea_writer em tentativa 2 vê somente justificativas de quem REPROVOU" do
      Mock.set_script(:idea_writer, ["v1", "v2"])

      Mock.set_script(:idea_writer_review, [
        ~s({"score": 9, "justification": "APPROVED_IDEA_JUSTIFICATION"}),
        ~s({"score": 9, "justification": "ok v2"})
      ])

      Mock.set_script(:technical_researcher, [
        ~s({"score": 3, "justification": "REJECTED_TECH_JUSTIFICATION"}),
        ~s({"score": 9, "justification": "ok v2"})
      ])

      Mock.set_script(:qa, [
        ~s({"score": 9, "justification": "APPROVED_QA_JUSTIFICATION"}),
        ~s({"score": 9, "justification": "ok v2"})
      ])

      Orchestrator.evaluate("tarefa", llm_client: Mock, max_attempts: 2, threshold: 7)

      calls = Mock.calls()

      idea_writer_calls =
        calls
        |> Enum.filter(&(&1.opts[:role] == :idea_writer))
        |> Enum.reverse()

      assert length(idea_writer_calls) == 2
      second_call_content = Enum.at(idea_writer_calls, 1).messages |> Enum.map_join("\n", & &1.content)

      assert second_call_content =~ "REJECTED_TECH_JUSTIFICATION",
             "idea_writer deveria ver feedback de quem reprovou"

      refute second_call_content =~ "APPROVED_QA_JUSTIFICATION",
             "idea_writer não deveria ver justificativa de quem aprovou (isolamento de narrativa)"

      refute second_call_content =~ "APPROVED_IDEA_JUSTIFICATION",
             "idea_writer não deveria ver própria self-review aprovada"
    end
  end
end
