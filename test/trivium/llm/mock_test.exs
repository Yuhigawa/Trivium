defmodule Trivium.LLM.MockTest do
  use ExUnit.Case, async: false

  alias Trivium.LLM.Mock

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  describe "complete/3" do
    test "consome respostas do script na ordem" do
      Mock.set_script(:my_role, ["first", "second", "third"])

      assert {:ok, "first"} = Mock.complete("model", [], role: :my_role)
      assert {:ok, "second"} = Mock.complete("model", [], role: :my_role)
      assert {:ok, "third"} = Mock.complete("model", [], role: :my_role)
    end

    test "retorna default quando script está vazio" do
      assert {:ok, text} = Mock.complete("model", [], role: :unknown)
      assert text =~ ~s("score")
    end

    test "usa model como chave quando :role ausente" do
      Mock.set_script("special-model", ["by-model"])
      assert {:ok, "by-model"} = Mock.complete("special-model", [], [])
    end

    test "registra todas as chamadas" do
      messages = [%{role: "user", content: "hello"}]
      Mock.complete("m", messages, role: :r)
      Mock.complete("m", messages, role: :r)

      calls = Mock.calls()
      assert length(calls) == 2
      assert Enum.all?(calls, &(&1.model == "m"))
    end

    test "script vazio depois de consumir continua dando default" do
      Mock.set_script(:r, ["one"])
      assert {:ok, "one"} = Mock.complete("m", [], role: :r)
      assert {:ok, text} = Mock.complete("m", [], role: :r)
      assert text =~ ~s("score")
    end
  end

  describe "stream/4" do
    test "entrega texto inteiro no chunk_handler" do
      Mock.set_script(:r, ["streamed"])
      parent = self()
      cb = fn chunk -> send(parent, {:chunk, chunk}) end

      assert {:ok, "streamed"} = Mock.stream("m", [], [role: :r], cb)
      assert_receive {:chunk, "streamed"}
    end
  end

  describe "reset/0" do
    test "limpa scripts e calls" do
      Mock.set_script(:r, ["x"])
      Mock.complete("m", [], role: :r)

      Mock.reset()

      assert Mock.calls() == []
      assert {:ok, text} = Mock.complete("m", [], role: :r)
      assert text =~ ~s("score")
    end
  end
end
