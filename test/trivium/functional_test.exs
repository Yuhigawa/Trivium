defmodule Trivium.FunctionalTest do
  @moduledoc """
  Testes funcionais end-to-end. Validam o pipeline completo:
  Mock LLM → Orchestrator → Events → Report. Sem I/O real de rede/CLI.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Trivium.{Orchestrator, REPL, Renderer, Report}
  alias Trivium.LLM.Mock
  alias Trivium.Types.{Idea, Result}

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  @markdown_idea """
  ## Problema
  Usuários não têm contador simples.

  ## Solução
  Um contador digital mínimo.

  ## Escopo
  Botões + e -.

  ## Fora de escopo
  Persistência.

  ## Critérios de sucesso
  Clicar atualiza.
  """

  defp approve_everyone do
    Mock.set_script(:idea_writer, [@markdown_idea])
    Mock.set_script(:idea_writer_review, [~s({"score": 9, "justification": "clara"})])
    Mock.set_script(:technical_researcher, [~s({"score": 9, "justification": "trivial"})])
    Mock.set_script(:qa, [~s({"score": 8, "justification": "testável"})])
  end

  describe "pipeline feliz: orchestrator + events + report" do
    test "aprova e produz Report com status ✅ APPROVED" do
      approve_everyone()

      result =
        Orchestrator.evaluate("criar contador simples",
          llm_client: Mock,
          max_attempts: 3,
          threshold: 7
        )

      assert %Result{status: :approved, attempts: [_], final_reviews: reviews, final_idea: idea} =
               result

      assert length(reviews) == 3
      assert Enum.all?(reviews, &(&1.score > 7))
      assert %Idea{content: content} = idea
      assert content =~ "Problema"

      report = Report.format(result)
      assert report =~ "APPROVED"
      assert report =~ "Scores"
      assert report =~ "9/10"
      assert report =~ "idea-writer"
      assert report =~ "tech-research"
      assert report =~ "qa"
    end
  end

  describe "pipeline de reprovação + refinamento" do
    test "falha, refina e aprova — relatório final mostra última ideia vencedora" do
      Mock.set_script(:idea_writer, ["ideia_v1_rascunho", @markdown_idea])

      Mock.set_script(:idea_writer_review, [
        ~s({"score": 9, "justification": "ok v1"}),
        ~s({"score": 9, "justification": "ok v2"})
      ])

      Mock.set_script(:technical_researcher, [
        ~s({"score": 3, "justification": "muito vago"}),
        ~s({"score": 9, "justification": "agora sim"})
      ])

      Mock.set_script(:qa, [
        ~s({"score": 9, "justification": "ok v1"}),
        ~s({"score": 8, "justification": "ok v2"})
      ])

      result = Orchestrator.evaluate("tarefa", llm_client: Mock, max_attempts: 3, threshold: 7)

      assert result.status == :approved
      assert length(result.attempts) == 2
      assert %Idea{content: content} = result.final_idea
      assert content =~ "Problema"

      report = Report.format(result)
      assert report =~ "APPROVED after 2 attempt"
    end

    test "esgota tentativas e relatório mostra REJECTED + histórico" do
      Mock.set_script(:idea_writer, ["v1", "v2", "v3"])

      Mock.set_script(:idea_writer_review, [
        ~s({"score": 3, "justification": "x"}),
        ~s({"score": 3, "justification": "x"}),
        ~s({"score": 3, "justification": "x"})
      ])

      Mock.set_script(:technical_researcher, [
        ~s({"score": 3, "justification": "y"}),
        ~s({"score": 3, "justification": "y"}),
        ~s({"score": 3, "justification": "y"})
      ])

      Mock.set_script(:qa, [
        ~s({"score": 3, "justification": "z"}),
        ~s({"score": 3, "justification": "z"}),
        ~s({"score": 3, "justification": "z"})
      ])

      result = Orchestrator.evaluate("tarefa", llm_client: Mock, max_attempts: 3, threshold: 7)

      assert result.status == :rejected
      assert length(result.attempts) == 3

      report = Report.format(result)
      assert report =~ "REJECTED"
      assert report =~ "Attempt history"
      assert report =~ "attempt 1"
      assert report =~ "attempt 3"
    end
  end

  describe "pipeline com renderer ativo (eventos + I/O)" do
    test "Renderer captura eventos de sessão real do Orchestrator" do
      approve_everyone()
      session_id = make_ref()

      output =
        capture_io(fn ->
          renderer = Renderer.start(session_id)

          Orchestrator.evaluate("tarefa X",
            session_id: session_id,
            llm_client: Mock,
            max_attempts: 1,
            threshold: 7
          )

          Process.sleep(100)
          Renderer.stop(renderer)
          Process.sleep(50)
        end)

      assert output =~ "Starting evaluation"
      assert output =~ "attempt 1/1"
      assert output =~ "approved"
    end
  end

  describe "REPL funcional" do
    test "ignora linhas vazias e sai com 'exit'" do
      stdin = "\n\nexit\n"

      output =
        capture_io(stdin, fn ->
          REPL.start(llm_client: Mock, stream: false)
        end)

      assert output =~ "Trivium"
      assert output =~ "bye"
    end

    test "processa task e imprime relatório entre prompts" do
      approve_everyone()

      stdin = "criar feature X\nexit\n"

      output =
        capture_io(stdin, fn ->
          REPL.start(llm_client: Mock, stream: false, max_attempts: 1)
        end)

      assert output =~ "APPROVED"
      assert output =~ "Scores"
      assert output =~ "bye"
    end

    test "EOF (Ctrl-D) termina REPL cleanly" do
      output =
        capture_io("", fn ->
          REPL.start(llm_client: Mock, stream: false)
        end)

      assert output =~ "Trivium"
      assert output =~ "bye"
    end
  end
end
