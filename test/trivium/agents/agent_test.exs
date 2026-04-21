defmodule Trivium.Agents.AgentTest do
  use ExUnit.Case, async: true

  alias Trivium.Agents.Agent

  describe "parse_review/2" do
    test "extrai JSON simples" do
      text = ~s({"score": 8, "justification": "boa ideia"})

      assert {:ok, review} = Agent.parse_review(text, :qa)
      assert review.score == 8
      assert review.justification == "boa ideia"
      assert review.role == :qa
    end

    test "extrai JSON embutido em texto conversacional" do
      text = ~s(Aqui está minha avaliação: {"score": 6, "justification": "falta detalhe"})

      assert {:ok, review} = Agent.parse_review(text, :technical_researcher)
      assert review.score == 6
    end

    test "clampa float para integer válido" do
      text = ~s({"score": 7.0, "justification": "ok"})
      assert {:ok, review} = Agent.parse_review(text, :qa)
      assert review.score == 7
    end

    test "rejeita score fora do range" do
      text = ~s({"score": 15, "justification": "x"})
      assert {:error, _} = Agent.parse_review(text, :qa)
    end

    test "rejeita quando não acha JSON" do
      text = "sem json nenhum aqui"
      assert {:error, {:no_json_found, _}} = Agent.parse_review(text, :qa)
    end
  end
end
