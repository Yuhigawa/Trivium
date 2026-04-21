defmodule Trivium.Agents.ProjectModeTest do
  @moduledoc """
  Valida que cada agente ramifica o system prompt por tipo de tarefa e que
  o project_context propaga o path + tools readonly para o LLM client.
  """
  use ExUnit.Case, async: false

  alias Trivium.Agents.{IdeaWriter, QA, TechnicalResearcher}
  alias Trivium.LLM.Mock
  alias Trivium.Types.{Idea, ProjectContext}

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  describe "system_prompt/1" do
    test "IdeaWriter: prompt muda por tipo" do
      bug_p = IdeaWriter.system_prompt(%ProjectContext{path: "/x", type: :bug_fix, task: "t"})
      feat_p = IdeaWriter.system_prompt(%ProjectContext{path: "/x", type: :feature, task: "t"})

      ana_p =
        IdeaWriter.system_prompt(%ProjectContext{path: "/x", type: :analysis, task: "t"})

      none_p = IdeaWriter.system_prompt(nil)

      assert bug_p =~ "root-cause"
      assert bug_p =~ "Causa-raiz"
      assert feat_p =~ "Problema"
      assert feat_p =~ "Solução"
      assert ana_p =~ "Findings"
      assert ana_p =~ "Recomendações"
      assert none_p == feat_p, "sem contexto deve cair no prompt de feature (default)"
    end

    test "TechnicalResearcher: prompt muda por tipo" do
      bug_p =
        TechnicalResearcher.system_prompt(%ProjectContext{
          path: "/x",
          type: :bug_fix,
          task: "t"
        })

      feat_p =
        TechnicalResearcher.system_prompt(%ProjectContext{
          path: "/x",
          type: :feature,
          task: "t"
        })

      ana_p =
        TechnicalResearcher.system_prompt(%ProjectContext{
          path: "/x",
          type: :analysis,
          task: "t"
        })

      assert bug_p =~ "causa-raiz"
      assert feat_p =~ "Viabilidade"
      assert ana_p =~ "Profundidade" or ana_p =~ "findings"
    end

    test "QA: prompt muda por tipo" do
      bug_p = QA.system_prompt(%ProjectContext{path: "/x", type: :bug_fix, task: "t"})
      feat_p = QA.system_prompt(%ProjectContext{path: "/x", type: :feature, task: "t"})
      ana_p = QA.system_prompt(%ProjectContext{path: "/x", type: :analysis, task: "t"})

      assert bug_p =~ "regressão" or bug_p =~ "Regressão"
      assert feat_p =~ "testabilidade"
      assert ana_p =~ "ACIONABILIDADE" or ana_p =~ "acionab"
    end
  end

  describe "IdeaWriter.run/3 com project_context" do
    setup do
      Mock.set_script(:idea_writer, ["markdown output"])
      :ok
    end

    test "propaga add_dir e allowed_tools nas opts do LLM" do
      ctx = %ProjectContext{path: "/tmp", type: :bug_fix, task: "t"}

      IdeaWriter.run("tarefa", [], llm_client: Mock, project_context: ctx)

      [call] = Mock.calls()
      assert call.opts[:add_dir] == "/tmp"
      assert call.opts[:allowed_tools] == "Read Grep Glob"
      assert call.opts[:role] == :idea_writer
    end

    test "user message inclui path e type quando há project_context" do
      ctx = %ProjectContext{path: "/meu/proj", type: :analysis, task: "mapear auth"}

      IdeaWriter.run("mapear auth", [], llm_client: Mock, project_context: ctx)

      [call] = Mock.calls()
      user_msg = Enum.find(call.messages, &(&1.role == "user"))
      assert user_msg.content =~ "/meu/proj"
      assert user_msg.content =~ "analysis"
    end

    test "sem project_context, NÃO inclui add_dir/allowed_tools" do
      IdeaWriter.run("tarefa", [], llm_client: Mock)

      [call] = Mock.calls()
      refute Keyword.has_key?(call.opts, :add_dir)
      refute Keyword.has_key?(call.opts, :allowed_tools)
    end

    test "prompt system escolhido ramifica por tipo do context" do
      ctx = %ProjectContext{path: "/tmp", type: :bug_fix, task: "t"}
      IdeaWriter.run("tarefa", [], llm_client: Mock, project_context: ctx)

      [call] = Mock.calls()
      sys = Enum.find(call.messages, &(&1.role == "system"))
      assert sys.content =~ "Causa-raiz"
    end
  end

  describe "TechnicalResearcher.run/2 com project_context" do
    test "propaga add_dir e allowed_tools" do
      Mock.set_script(:technical_researcher, [~s({"score": 8, "justification": "ok"})])
      ctx = %ProjectContext{path: "/tmp", type: :feature, task: "t"}

      TechnicalResearcher.run(%Idea{content: "x"}, llm_client: Mock, project_context: ctx)

      [call] = Mock.calls()
      assert call.opts[:add_dir] == "/tmp"
      assert call.opts[:allowed_tools] == "Read Grep Glob"
    end

    test "muda prompt pro bug_fix" do
      Mock.set_script(:technical_researcher, [~s({"score": 8, "justification": "ok"})])
      ctx = %ProjectContext{path: "/tmp", type: :bug_fix, task: "t"}

      TechnicalResearcher.run(%Idea{content: "x"}, llm_client: Mock, project_context: ctx)

      [call] = Mock.calls()
      sys = Enum.find(call.messages, &(&1.role == "system"))
      assert sys.content =~ "causa-raiz"
    end
  end

  describe "QA.run/2 com project_context" do
    test "propaga add_dir e allowed_tools" do
      Mock.set_script(:qa, [~s({"score": 8, "justification": "ok"})])
      ctx = %ProjectContext{path: "/tmp", type: :analysis, task: "t"}

      QA.run(%Idea{content: "x"}, llm_client: Mock, project_context: ctx)

      [call] = Mock.calls()
      assert call.opts[:add_dir] == "/tmp"
      assert call.opts[:allowed_tools] == "Read Grep Glob"
    end

    test "muda prompt pra analysis" do
      Mock.set_script(:qa, [~s({"score": 8, "justification": "ok"})])
      ctx = %ProjectContext{path: "/tmp", type: :analysis, task: "t"}

      QA.run(%Idea{content: "x"}, llm_client: Mock, project_context: ctx)

      [call] = Mock.calls()
      sys = Enum.find(call.messages, &(&1.role == "system"))
      assert sys.content =~ "acionab" or sys.content =~ "ACIONABILIDADE"
    end
  end
end
