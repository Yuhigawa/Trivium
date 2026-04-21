defmodule Trivium.LLM.AnthropicTest do
  use ExUnit.Case, async: true

  alias Trivium.LLM.Anthropic

  describe "split_system/1" do
    test "separa system e retorna resto intacto" do
      messages = [
        %{role: "system", content: "you are X"},
        %{role: "user", content: "hi"}
      ]

      assert {"you are X", [%{role: "user", content: "hi"}]} = Anthropic.split_system(messages)
    end

    test "concatena múltiplas system messages com \\n\\n" do
      messages = [
        %{role: "system", content: "part1"},
        %{role: "system", content: "part2"},
        %{role: "user", content: "hi"}
      ]

      assert {"part1\n\npart2", _rest} = Anthropic.split_system(messages)
    end

    test "retorna nil quando não há system" do
      messages = [%{role: "user", content: "hi"}]
      assert {nil, [%{role: "user", content: "hi"}]} = Anthropic.split_system(messages)
    end

    test "aceita atom ou string como chave de role" do
      messages = [
        %{"role" => "system", "content" => "sys"},
        %{"role" => "user", "content" => "u"}
      ]

      assert {"sys", [%{role: "user", content: "u"}]} = Anthropic.split_system(messages)
    end
  end

  describe "build_body/4" do
    test "inclui system quando presente" do
      body = Anthropic.build_body("m", [
        %{role: "system", content: "sys"},
        %{role: "user", content: "hi"}
      ], [], false)

      assert body.model == "m"
      assert body.system == "sys"
      assert body.messages == [%{role: "user", content: "hi"}]
      refute Map.has_key?(body, :stream)
    end

    test "omite system quando ausente" do
      body = Anthropic.build_body("m", [%{role: "user", content: "hi"}], [], false)
      refute Map.has_key?(body, :system)
    end

    test "adiciona stream: true quando pedido" do
      body = Anthropic.build_body("m", [%{role: "user", content: "hi"}], [], true)
      assert body.stream == true
    end

    test "respeita max_tokens opcional" do
      body = Anthropic.build_body("m", [%{role: "user", content: "hi"}], [max_tokens: 500], false)
      assert body.max_tokens == 500
    end

    test "max_tokens tem default" do
      body = Anthropic.build_body("m", [%{role: "user", content: "hi"}], [], false)
      assert is_integer(body.max_tokens)
      assert body.max_tokens > 0
    end
  end

  describe "extract_text/1" do
    test "concatena todos os blocos text" do
      resp = %{
        "content" => [
          %{"type" => "text", "text" => "hello "},
          %{"type" => "text", "text" => "world"}
        ]
      }

      assert Anthropic.extract_text(resp) == "hello world"
    end

    test "ignora blocos não-text" do
      resp = %{
        "content" => [
          %{"type" => "text", "text" => "ok"},
          %{"type" => "tool_use", "id" => "x"}
        ]
      }

      assert Anthropic.extract_text(resp) == "ok"
    end

    test "retorna string vazia para resposta inesperada" do
      assert Anthropic.extract_text(%{}) == ""
      assert Anthropic.extract_text(nil) == ""
    end
  end

  describe "parse_sse_chunks/1" do
    test "extrai texto de content_block_delta" do
      data = ~s(data: {"type":"content_block_delta","delta":{"text":"hello"}}\n\n)
      assert Anthropic.parse_sse_chunks(data) == ["hello"]
    end

    test "ignora outros tipos de evento" do
      data = """
      event: message_start
      data: {"type":"message_start"}

      data: {"type":"content_block_delta","delta":{"text":"abc"}}

      data: {"type":"message_stop"}
      """

      assert Anthropic.parse_sse_chunks(data) == ["abc"]
    end

    test "múltiplos deltas em mesmo buffer" do
      data = """
      data: {"type":"content_block_delta","delta":{"text":"one"}}
      data: {"type":"content_block_delta","delta":{"text":"two"}}
      """

      assert Anthropic.parse_sse_chunks(data) == ["one", "two"]
    end

    test "linhas sem 'data:' são ignoradas" do
      data = "garbage line\nevent: foo\n"
      assert Anthropic.parse_sse_chunks(data) == []
    end

    test "JSON inválido num data line não quebra parsing" do
      data = """
      data: not json
      data: {"type":"content_block_delta","delta":{"text":"ok"}}
      """

      assert Anthropic.parse_sse_chunks(data) == ["ok"]
    end
  end
end
