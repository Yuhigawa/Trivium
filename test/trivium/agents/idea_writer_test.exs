defmodule Trivium.Agents.IdeaWriterTest do
  use ExUnit.Case, async: false

  alias Trivium.Agents.IdeaWriter
  alias Trivium.LLM.Mock
  alias Trivium.Types.{Attempt, Idea, Review}

  setup do
    case Process.whereis(Mock) do
      nil -> Mock.start_link([])
      _ -> Mock.reset()
    end

    :ok
  end

  describe "role/0" do
    test "returns :idea_writer" do
      assert IdeaWriter.role() == :idea_writer
    end
  end

  describe "run/3 sem previous_attempts" do
    test "retorna %Idea{} com content trimmed" do
      Mock.set_script(:idea_writer, ["  ## Problema\nX\n"])

      assert {:ok, %Idea{content: "## Problema\nX"}} =
               IdeaWriter.run("criar X", [], llm_client: Mock)
    end

    test "prompt NÃO contém bloco 'Tentativas anteriores'" do
      Mock.set_script(:idea_writer, ["idea"])
      IdeaWriter.run("tarefa Y", [], llm_client: Mock)

      [call] = Mock.calls()
      all_content = call.messages |> Enum.map_join("\n", & &1.content)

      refute all_content =~ "Tentativas anteriores"
      assert all_content =~ "tarefa Y"
    end
  end

  describe "run/3 com previous_attempts" do
    test "inclui justificativas dos que reprovaram" do
      previous = [
        %Attempt{
          n: 1,
          idea: %Idea{content: "v1"},
          reviews: [
            %Review{role: :technical_researcher, score: 3, justification: "MUITO_RASO"},
            %Review{role: :qa, score: 9, justification: "approved"}
          ]
        }
      ]

      Mock.set_script(:idea_writer, ["v2"])
      IdeaWriter.run("tarefa", previous, llm_client: Mock)

      [call] = Mock.calls()
      content = call.messages |> Enum.map_join("\n", & &1.content)

      assert content =~ "MUITO_RASO"
      refute content =~ "approved"
    end

    test "inclui conteúdo da ideia anterior pra contexto" do
      previous = [
        %Attempt{
          n: 1,
          idea: %Idea{content: "IDEIA_V1_UNICO_STRING"},
          reviews: [%Review{role: :qa, score: 3, justification: "vago"}]
        }
      ]

      Mock.set_script(:idea_writer, ["v2"])
      IdeaWriter.run("tarefa", previous, llm_client: Mock)

      [call] = Mock.calls()
      content = call.messages |> Enum.map_join("\n", & &1.content)
      assert content =~ "IDEIA_V1_UNICO_STRING"
    end

    test "propaga erro do client" do
      defmodule FailingClient do
        @behaviour Trivium.LLM.Client
        @impl true
        def complete(_, _, _), do: {:error, :boom}
        @impl true
        def stream(_, _, _, _), do: {:error, :boom}
      end

      assert {:error, :boom} = IdeaWriter.run("t", [], llm_client: FailingClient)
    end
  end

  describe "self_review/2" do
    test "retorna %Review{} quando LLM devolve JSON válido" do
      Mock.set_script(:idea_writer_review, [~s({"score": 9, "justification": "boa"})])

      assert {:ok, %Review{role: :idea_writer, score: 9, justification: "boa"}} =
               IdeaWriter.self_review(%Idea{content: "x"}, llm_client: Mock)
    end

    test "usa key distinta de :idea_writer para evitar consumir script de geração" do
      Mock.set_script(:idea_writer, ["geração"])
      Mock.set_script(:idea_writer_review, [~s({"score": 8, "justification": "ok"})])

      {:ok, _review} = IdeaWriter.self_review(%Idea{content: "x"}, llm_client: Mock)

      # script do :idea_writer deve permanecer intocado
      assert {:ok, "geração"} = Mock.complete("m", [], role: :idea_writer)
    end

    test "propaga erro de parse quando JSON inválido" do
      Mock.set_script(:idea_writer_review, ["texto sem json"])

      assert {:error, _reason} =
               IdeaWriter.self_review(%Idea{content: "x"}, llm_client: Mock)
    end
  end
end
