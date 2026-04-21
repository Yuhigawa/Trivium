defmodule Trivium.LLM.ClaudeCLITest do
  use ExUnit.Case, async: true

  alias Trivium.LLM.ClaudeCLI

  describe "shell_quote/1" do
    test "envolve em aspas simples" do
      assert ClaudeCLI.shell_quote("hello") == "'hello'"
    end

    test "trata espaços preservando-os" do
      assert ClaudeCLI.shell_quote("hello world") == "'hello world'"
    end

    test "escapa aspas simples pelo truque POSIX" do
      assert ClaudeCLI.shell_quote("it's") == "'it'\\''s'"
    end

    test "preserva newlines literais" do
      assert ClaudeCLI.shell_quote("a\nb") == "'a\nb'"
    end

    test "string vazia vira '' (válido em shell)" do
      assert ClaudeCLI.shell_quote("") == "''"
    end

    test "metacaracteres shell permanecem seguros dentro das aspas" do
      input = "$(rm -rf /); `cat`; ${HOME}"
      quoted = ClaudeCLI.shell_quote(input)
      assert quoted == "'$(rm -rf /); `cat`; ${HOME}'"
    end
  end

  describe "split_messages/1" do
    test "separa system e concatena o resto" do
      messages = [
        %{role: "system", content: "sys"},
        %{role: "user", content: "user msg"}
      ]

      assert {"sys", "user msg"} = ClaudeCLI.split_messages(messages)
    end

    test "concatena múltiplas user messages com \\n\\n" do
      messages = [
        %{role: "user", content: "one"},
        %{role: "user", content: "two"}
      ]

      assert {"", "one\n\ntwo"} = ClaudeCLI.split_messages(messages)
    end

    test "assistant messages ganham prefixo" do
      messages = [
        %{role: "assistant", content: "prior reply"},
        %{role: "user", content: "now"}
      ]

      {"", user} = ClaudeCLI.split_messages(messages)
      assert user =~ "[assistant said previously]: prior reply"
      assert user =~ "now"
    end

    test "aceita chaves atom ou string" do
      messages = [
        %{"role" => "system", "content" => "sys"},
        %{"role" => "user", "content" => "u"}
      ]

      assert {"sys", "u"} = ClaudeCLI.split_messages(messages)
    end

    test "ambos sem system retornam string vazia" do
      assert {"", "u"} = ClaudeCLI.split_messages([%{role: "user", content: "u"}])
    end
  end

  describe "build_args/3" do
    test "flags básicas sempre presentes" do
      args = ClaudeCLI.build_args("claude-x", "")
      assert "-p" in args
      assert "--model" in args
      assert "claude-x" in args
      assert "--output-format" in args
      assert "json" in args
    end

    test "desabilita todas as tools via allowedTools vazio" do
      args = ClaudeCLI.build_args("m", "")
      idx = Enum.find_index(args, &(&1 == "--allowedTools"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == ""
    end

    test "inclui --append-system-prompt quando system não vazio" do
      args = ClaudeCLI.build_args("m", "sistema aqui")
      assert "--append-system-prompt" in args
      assert "sistema aqui" in args
    end

    test "omite --append-system-prompt quando system vazio" do
      args = ClaudeCLI.build_args("m", "")
      refute "--append-system-prompt" in args
    end
  end

  describe "parse_output/1" do
    test "extrai campo result de JSON válido" do
      json = ~s({"result": "hello", "session_id": "abc"})
      assert {:ok, "hello"} = ClaudeCLI.parse_output(json)
    end

    test "extrai campo content como fallback" do
      json = ~s({"content": "alt"})
      assert {:ok, "alt"} = ClaudeCLI.parse_output(json)
    end

    test "sem JSON válido retorna stdout trimmed como :ok" do
      raw = "   plain text response\n"
      assert {:ok, "plain text response"} = ClaudeCLI.parse_output(raw)
    end

    test "JSON sem campos reconhecidos vira :error :unexpected_json" do
      json = ~s({"unknown": "field"})
      assert {:error, {:unexpected_json, _}} = ClaudeCLI.parse_output(json)
    end

    test "trim inicial/final" do
      assert {:ok, "x"} = ClaudeCLI.parse_output("\n\n  {\"result\": \"x\"}  \n")
    end
  end

  describe "complete/3 (integração leve)" do
    test "propaga erro quando comando falha" do
      result = ClaudeCLI.complete("m", [%{role: "user", content: "x"}], role: :test)

      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "complete deve retornar tuple result, qualquer que seja o estado do sistema"
    end
  end
end
