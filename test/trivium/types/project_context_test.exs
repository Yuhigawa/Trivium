defmodule Trivium.Types.ProjectContextTest do
  use ExUnit.Case, async: true

  alias Trivium.Types.ProjectContext

  @valid_path "/tmp"

  describe "struct" do
    test "exige path, type e task" do
      assert_raise ArgumentError, fn -> struct!(ProjectContext, []) end
      assert_raise ArgumentError, fn -> struct!(ProjectContext, path: "/x") end
      assert_raise ArgumentError, fn -> struct!(ProjectContext, path: "/x", type: :bug_fix) end
    end

    test "cria com os três campos" do
      ctx = %ProjectContext{path: "/x", type: :feature, task: "t"}
      assert ctx.path == "/x"
      assert ctx.type == :feature
      assert ctx.task == "t"
    end
  end

  describe "valid_types/0" do
    test "retorna os tipos suportados" do
      types = ProjectContext.valid_types()
      assert :bug_fix in types
      assert :feature in types
      assert :analysis in types
    end
  end

  describe "validate/1" do
    test "aceita contexto válido" do
      ctx = %ProjectContext{path: @valid_path, type: :feature, task: "criar X"}
      assert {:ok, ^ctx} = ProjectContext.validate(ctx)
    end

    test "aceita os 3 tipos suportados" do
      for type <- [:bug_fix, :feature, :analysis] do
        ctx = %ProjectContext{path: @valid_path, type: type, task: "x"}
        assert {:ok, _} = ProjectContext.validate(ctx)
      end
    end

    test "rejeita tipo inválido" do
      ctx = %ProjectContext{path: @valid_path, type: :refactor, task: "x"}
      assert {:error, {:invalid_type, :refactor}} = ProjectContext.validate(ctx)
    end

    test "rejeita path que não é diretório" do
      ctx = %ProjectContext{path: "/non/existent/dir/xyz", type: :feature, task: "t"}
      assert {:error, {:invalid_path, _}} = ProjectContext.validate(ctx)
    end

    test "rejeita path que é arquivo, não diretório" do
      path = Path.join(System.tmp_dir!(), "trivium_file_#{System.unique_integer([:positive])}")
      File.write!(path, "hi")
      on_exit(fn -> File.rm(path) end)

      ctx = %ProjectContext{path: path, type: :feature, task: "t"}
      assert {:error, {:invalid_path, ^path}} = ProjectContext.validate(ctx)
    end

    test "rejeita task vazia" do
      ctx = %ProjectContext{path: @valid_path, type: :feature, task: ""}
      assert {:error, :empty_task} = ProjectContext.validate(ctx)
    end

    test "rejeita task só com whitespace" do
      ctx = %ProjectContext{path: @valid_path, type: :feature, task: "   \n\t  "}
      assert {:error, :empty_task} = ProjectContext.validate(ctx)
    end
  end
end
