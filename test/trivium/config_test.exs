defmodule Trivium.ConfigTest do
  use ExUnit.Case, async: false

  alias Trivium.Config

  setup do
    original = Application.get_all_env(:trivium)
    on_exit(fn -> Enum.each(original, fn {k, v} -> Application.put_env(:trivium, k, v) end) end)
    :ok
  end

  describe "get/2" do
    test "retorna valor existente" do
      Application.put_env(:trivium, :test_key, :hello)
      assert Config.get(:test_key) == :hello
    end

    test "retorna default quando ausente" do
      Application.delete_env(:trivium, :missing_key)
      assert Config.get(:missing_key, :default) == :default
    end

    test "retorna nil por padrão quando ausente e sem default" do
      Application.delete_env(:trivium, :missing_key)
      assert Config.get(:missing_key) == nil
    end
  end

  describe "put/2" do
    test "atualiza env var runtime" do
      Config.put(:runtime_key, 42)
      assert Config.get(:runtime_key) == 42
    end
  end

  describe "model_for/1" do
    test "retorna modelo para papéis válidos" do
      Application.put_env(:trivium, :models, %{
        idea_writer: "model-a",
        technical_researcher: "model-b",
        qa: "model-c"
      })

      assert Config.model_for(:idea_writer) == "model-a"
      assert Config.model_for(:technical_researcher) == "model-b"
      assert Config.model_for(:qa) == "model-c"
    end

    test "raises para papel inválido (guard)" do
      assert_raise FunctionClauseError, fn ->
        Config.model_for(:invalid_role)
      end
    end

    test "raises quando papel não está no map de models" do
      Application.put_env(:trivium, :models, %{idea_writer: "x"})
      assert_raise KeyError, fn -> Config.model_for(:qa) end
    end
  end

  describe "api_key/0" do
    test "prioriza env var ANTHROPIC_API_KEY" do
      System.put_env("ANTHROPIC_API_KEY", "env-value")
      Application.put_env(:trivium, :api_key, "config-value")

      assert Config.api_key() == "env-value"

      System.delete_env("ANTHROPIC_API_KEY")
    end

    test "faz fallback pra config quando env está vazia ou ausente" do
      System.delete_env("ANTHROPIC_API_KEY")
      Application.put_env(:trivium, :api_key, "config-value")
      assert Config.api_key() == "config-value"
    end

    test "trata string vazia como ausência" do
      System.put_env("ANTHROPIC_API_KEY", "")
      Application.put_env(:trivium, :api_key, "config-value")
      assert Config.api_key() == "config-value"
      System.delete_env("ANTHROPIC_API_KEY")
    end
  end

  describe "defaults sensatos" do
    test "max_attempts default 3" do
      Application.delete_env(:trivium, :max_attempts)
      assert Config.max_attempts() == 3
    end

    test "approval_threshold default 7" do
      Application.delete_env(:trivium, :approval_threshold)
      assert Config.approval_threshold() == 7
    end

    test "llm_client default é Anthropic" do
      Application.delete_env(:trivium, :llm_client)
      assert Config.llm_client() == Trivium.LLM.Anthropic
    end
  end
end
