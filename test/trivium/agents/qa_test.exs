defmodule Trivium.Agents.QATest do
  use ExUnit.Case, async: false

  alias Trivium.Agents.QA
  alias Trivium.LLM.Mock
  alias Trivium.Types.{Idea, Review}

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  test "role/0 retorna :qa" do
    assert QA.role() == :qa
  end

  describe "run/2" do
    test "devolve Review com role :qa" do
      Mock.set_script(:qa, [~s({"score": 8, "justification": "testável"})])

      assert {:ok, %Review{role: :qa, score: 8, justification: "testável"}} =
               QA.run(%Idea{content: "x"}, llm_client: Mock)
    end

    test "prompt system enfatiza testabilidade e critérios de aceite" do
      Mock.set_script(:qa, [~s({"score": 8, "justification": "ok"})])
      QA.run(%Idea{content: "x"}, llm_client: Mock)

      [call] = Mock.calls()
      system_msg = Enum.find(call.messages, &(&1.role == "system"))
      assert system_msg.content =~ "QA"
      assert system_msg.content =~ "testabilidade"
    end

    test "recebe somente a ideia (não recebe nada sobre outros avaliadores)" do
      Mock.set_script(:qa, [~s({"score": 7, "justification": "ok"})])
      QA.run(%Idea{content: "MINHA_IDEIA_UNICA"}, llm_client: Mock)

      [call] = Mock.calls()
      all = call.messages |> Enum.map_join("\n", & &1.content)

      assert all =~ "MINHA_IDEIA_UNICA"
      refute all =~ "technical_researcher"
      refute all =~ "tech-research"
    end

    test "erro de parse bloqueia avaliação" do
      Mock.set_script(:qa, ["nao tem json"])

      assert {:error, _} = QA.run(%Idea{content: "x"}, llm_client: Mock)
    end
  end
end
