defmodule Trivium.CLITest do
  use ExUnit.Case, async: true

  alias Trivium.CLI
  alias Trivium.Types.ProjectContext

  describe "plugin_version/0" do
    test "returns the version string from .claude-plugin/plugin.json" do
      assert is_binary(CLI.plugin_version())
      assert Regex.match?(~r/^\d+\.\d+\.\d+/, CLI.plugin_version())

      json_path = Path.expand("../../.claude-plugin/plugin.json", __DIR__)
      {:ok, json} = File.read(json_path)
      expected = Jason.decode!(json) |> Map.fetch!("version")
      assert CLI.plugin_version() == expected
    end
  end

  describe "project_context_from/1 — nenhuma flag" do
    test "retorna :none quando nenhuma das três está presente" do
      assert :none = CLI.project_context_from(path: nil, type: nil, task: nil)
      assert :none = CLI.project_context_from([])
    end
  end

  describe "project_context_from/1 — todas as flags" do
    test "constrói ProjectContext para feature" do
      assert {:ok, %ProjectContext{path: "/tmp", type: :feature, task: "criar X"}} =
               CLI.project_context_from(path: "/tmp", type: "feature", task: "criar X")
    end

    test "aceita 'bug' como alias de :bug_fix" do
      assert {:ok, %ProjectContext{type: :bug_fix}} =
               CLI.project_context_from(path: "/tmp", type: "bug", task: "x")
    end

    test "aceita 'bug_fix' literal" do
      assert {:ok, %ProjectContext{type: :bug_fix}} =
               CLI.project_context_from(path: "/tmp", type: "bug_fix", task: "x")
    end

    test "é case-insensitive em --type" do
      assert {:ok, %ProjectContext{type: :analysis}} =
               CLI.project_context_from(path: "/tmp", type: "Analysis", task: "x")
    end

    test "rejeita tipo desconhecido" do
      assert {:error, msg} =
               CLI.project_context_from(path: "/tmp", type: "refactor", task: "x")

      assert msg =~ "invalid --type"
    end

    test "rejeita path inexistente" do
      assert {:error, msg} =
               CLI.project_context_from(
                 path: "/non/existent/xyz",
                 type: "feature",
                 task: "x"
               )

      assert msg =~ "invalid --path"
    end

    test "rejeita task vazia" do
      assert {:error, msg} =
               CLI.project_context_from(path: "/tmp", type: "feature", task: "   ")

      assert msg =~ "--task"
    end
  end

  describe "project_context_from/1 — all-or-none" do
    test "erro quando só path" do
      assert {:error, msg} = CLI.project_context_from(path: "/tmp", type: nil, task: nil)
      assert msg =~ "all be provided together"
    end

    test "erro quando só path e type" do
      assert {:error, msg} =
               CLI.project_context_from(path: "/tmp", type: "feature", task: nil)

      assert msg =~ "all be provided together"
    end

    test "erro quando só task" do
      assert {:error, msg} = CLI.project_context_from(path: nil, type: nil, task: "x")
      assert msg =~ "all be provided together"
    end
  end
end
