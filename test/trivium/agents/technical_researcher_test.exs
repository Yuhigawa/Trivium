defmodule Trivium.Agents.TechnicalResearcherTest do
  use ExUnit.Case, async: false

  alias Trivium.Agents.TechnicalResearcher
  alias Trivium.LLM.Mock
  alias Trivium.Types.{Idea, Review}

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  test "role/0 retorna :technical_researcher" do
    assert TechnicalResearcher.role() == :technical_researcher
  end

  describe "run/2" do
    test "devolve Review com role correta" do
      Mock.set_script(:technical_researcher, [~s({"score": 7, "justification": "viável"})])

      assert {:ok, %Review{role: :technical_researcher, score: 7, justification: "viável"}} =
               TechnicalResearcher.run(%Idea{content: "x"}, llm_client: Mock)
    end

    test "recebe apenas a ideia no prompt" do
      Mock.set_script(:technical_researcher, [~s({"score": 8, "justification": "ok"})])
      TechnicalResearcher.run(%Idea{content: "IDEIA_UNICO_AQUI"}, llm_client: Mock)

      [call] = Mock.calls()
      content = call.messages |> Enum.map_join("\n", & &1.content)
      assert content =~ "IDEIA_UNICO_AQUI"
    end

    test "prompt system pede rigor e não sugerir melhorias" do
      Mock.set_script(:technical_researcher, [~s({"score": 8, "justification": "ok"})])
      TechnicalResearcher.run(%Idea{content: "x"}, llm_client: Mock)

      [call] = Mock.calls()
      system_msg = Enum.find(call.messages, &(&1.role == "system"))
      assert system_msg != nil
      assert system_msg.content =~ "TÉCNICO"
      assert system_msg.content =~ "INDEPENDENTE"
    end

    test "propaga erro de parse quando LLM não devolve JSON esperado" do
      Mock.set_script(:technical_researcher, ["zero json here"])

      assert {:error, _} = TechnicalResearcher.run(%Idea{content: "x"}, llm_client: Mock)
    end

    test "propaga erro quando score fora de range" do
      Mock.set_script(:technical_researcher, [~s({"score": 99, "justification": "x"})])

      assert {:error, {:score_out_of_range, 99}} =
               TechnicalResearcher.run(%Idea{content: "x"}, llm_client: Mock)
    end
  end
end
