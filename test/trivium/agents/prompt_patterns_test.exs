defmodule Trivium.Agents.PromptPatternsTest do
  @moduledoc """
  Asserts that the prompt-pattern borrowings from superpowers skills remain
  present in the agent system prompts. If someone edits a prompt and drops
  one of these markers, these tests fail — preventing silent drift.

  Patterns borrowed:
    - systematic-debugging → idea_writer bug_fix, technical_researcher bug_fix
    - writing-plans        → idea_writer feature
    - verification-before-completion → qa bug_fix
  """
  use ExUnit.Case, async: true

  alias Trivium.Agents.{IdeaWriter, QA, TechnicalResearcher}
  alias Trivium.Types.ProjectContext

  defp ctx(type), do: %ProjectContext{path: "/tmp", type: type, task: "x"}

  describe "systematic-debugging pattern" do
    test "idea_writer bug_fix prompt enumera os 4 passos estruturais" do
      prompt = IdeaWriter.system_prompt(ctx(:bug_fix))

      assert prompt =~ "Método"
      assert prompt =~ "reproduzir"
      assert prompt =~ "git blame" or prompt =~ "diff"
      assert prompt =~ "fluxo de dados"
      assert prompt =~ "MÍNIMA" or prompt =~ "mínima"
    end

    test "technical_researcher bug_fix prompt avalia rigor estrutural" do
      prompt = TechnicalResearcher.system_prompt(ctx(:bug_fix))

      assert prompt =~ "fluxo de dados"
      assert prompt =~ "MÍNIMO" or prompt =~ "mínimo"
    end
  end

  describe "writing-plans pattern" do
    test "idea_writer feature prompt exige WHY antes de HOW e escopo explícito" do
      prompt = IdeaWriter.system_prompt(ctx(:feature))

      assert prompt =~ "WHY" and prompt =~ "HOW"
      assert prompt =~ "não fazer" or prompt =~ "NÃO será feito"
      assert prompt =~ "Fora de escopo"
    end
  end

  describe "verification-before-completion pattern" do
    test "qa bug_fix prompt traz checklist antes de score alto" do
      prompt = QA.system_prompt(ctx(:bug_fix))

      assert prompt =~ "Checklist"
      assert prompt =~ "comando de teste"
      assert prompt =~ "output esperado"
    end

    test "checklist gate pros 3 itens mínimos" do
      prompt = QA.system_prompt(ctx(:bug_fix))

      # Deve haver os 3 checks essenciais numerados
      assert prompt =~ ~r/1\.\s/
      assert prompt =~ ~r/2\.\s/
      assert prompt =~ ~r/3\.\s/
    end
  end

  describe "isolamento mantido — patterns não estimulam coordenação" do
    test "nenhum prompt refere-se a output de outros agentes" do
      for type <- [:bug_fix, :feature, :analysis] do
        for mod <- [IdeaWriter, TechnicalResearcher, QA] do
          prompt = mod.system_prompt(ctx(type))

          refute prompt =~ "output do QA",
                 "#{mod} #{type} referencia QA"

          refute prompt =~ "technical_researcher review",
                 "#{mod} #{type} referencia tech review"

          refute prompt =~ "consultar outro agente",
                 "#{mod} #{type} sugere coordenação"
        end
      end
    end
  end
end
