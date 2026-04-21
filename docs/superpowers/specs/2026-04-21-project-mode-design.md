# Spec: Project Mode

## Context

Trivium hoje só avalia uma tarefa descrita em texto — os agentes raciocinam sem ver código algum. Isso limita o uso real: a grande maioria das tarefas de engenharia acontece no contexto de um projeto existente (corrigir bug, adicionar feature, levantar análise de código).

Este spec adiciona **project mode**: usuário passa path + tipo + descrição; os 3 agentes acessam o código real via tools read-only do Claude Code CLI; prompts ramificam conforme o tipo de tarefa. Isolamento entre agentes (premissa central do Trivium) permanece intacto — cada um lê o código por si.

Meta adicional: o usuário quer, no futuro, invocar Trivium **de dentro** de um projeto sendo editado com Claude Code. Interface one-shot via flags é obrigatória pra isso.

## Interface

```bash
trivium --path /proj --type <bug|feature|analysis> --task "<descrição>"
```

Comportamento:
- Flags `--path`, `--type`, `--task` têm que vir **todas ou nenhuma** (erro "all-or-none" caso contrário).
- Todas as três → modo one-shot: roda a avaliação, imprime relatório, sai.
- Nenhuma → REPL atual (backward-compat).

## Tipos de tarefa

| Tipo | idea-writer gera | technical avalia | qa avalia |
|---|---|---|---|
| `bug_fix` | Hipótese / Causa-raiz / Fix proposto / Validação / Critérios de sucesso | O fix endereça a causa-raiz? Solidez técnica? Riscos de regressão? | Fix é testável? Edge cases cobertos? Validação verificável? |
| `feature` | Problema / Solução / Escopo / Fora-de-escopo / Critérios (prompt atual) + integração com projeto existente | Viabilidade dentro do stack, complexidade, riscos de integração | Testabilidade, critérios mensuráveis, edge cases |
| `analysis` | Contexto / Findings / Recomendações / Riscos / Próximos passos (sem "solução proposta") | Profundidade técnica, cobertura dos arquivos certos, ausência de conclusões infundadas | Acionabilidade dos findings, ambiguidade, completude |

Scoring inalterado: cada agente dá nota 1-10, todos > 7 aprova; loop até 3 tentativas.

## Backend

Project mode exige **`Trivium.LLM.ClaudeCLI`** — porque precisamos que os agentes leiam arquivos e o `claude` CLI já traz Read/Grep/Glob. A API da Anthropic exigiria implementar tool-use do zero; fora de escopo nesta v1.

Validação: se usuário combinar `--path` com `llm_client: Trivium.LLM.Anthropic`, erro explícito na inicialização.

## Arquitetura

### Nova struct

```elixir
defmodule Trivium.Types.ProjectContext do
  @enforce_keys [:path, :type, :task]
  defstruct [:path, :type, :task]

  @types [:bug_fix, :feature, :analysis]

  def validate(%__MODULE__{} = ctx) do
    cond do
      ctx.type not in @types -> {:error, {:invalid_type, ctx.type}}
      not File.dir?(ctx.path) -> {:error, {:invalid_path, ctx.path}}
      String.trim(ctx.task || "") == "" -> {:error, :empty_task}
      true -> {:ok, ctx}
    end
  end
end
```

### Mudanças por módulo

1. **`Trivium.LLM.ClaudeCLI`**:
   - Novas opts aceitas em `complete/3`:
     - `:add_dir` → passa `--add-dir <path>` ao claude
     - `:allowed_tools` → sobrescreve `--allowedTools` (default: `""`; project mode: `"Read Grep Glob"`)
   - Helpers `build_args/3` ganham esses opts. Sem opts novos, comportamento inalterado.

2. **Agents (`IdeaWriter`, `TechnicalResearcher`, `QA`)**:
   - Cada agente aceita `:project_context` opcional em `run/3`.
   - Quando presente, o system prompt é escolhido via função `system_prompt/1` que casa no `ctx.type`.
   - O `run` propaga `add_dir: ctx.path` e `allowed_tools: "Read Grep Glob"` pro client LLM.
   - Quando ausente, mantém prompts atuais (sem break).

3. **`Trivium.Orchestrator.evaluate/2`**:
   - Aceita `:project_context` nas opts e repassa aos agentes em cada Task.
   - Lógica de fan-out/scoring inalterada.

4. **`Trivium.Report.format/1`**:
   - Quando Result carrega `project_context`, imprime bloco inicial:
     ```
     Project: /path/to/proj
     Type: bug_fix
     Task: login não funciona no mobile
     ```

5. **`Trivium.Types.Result`**:
   - Adicionar campo opcional `project_context :: ProjectContext.t() | nil`.

6. **`Trivium.CLI`**:
   - Optimus ganha 3 options: `--path`, `--type` (parser custom para atom), `--task`.
   - Após parse: if ≥1 das 3 preenchida E não todas → erro.
   - If todas → monta `%ProjectContext{}`, valida, bloqueia se Anthropic, roda one-shot: `Orchestrator.evaluate/2` → `Report.format/1` → `IO.puts/1` → `System.halt/1`.
   - Se nenhuma → REPL atual.

7. **`Trivium.REPL`**:
   - Sem mudanças nesta v1. (Opcional: fluxo interativo de project mode fica pra v2.)

## Testes

### Unit

- `Types.ProjectContext` — valida tipo, path, task vazia
- `LLM.ClaudeCLI.build_args/3` — `:add_dir` gera flag correta; `:allowed_tools` sobrescreve
- Cada agente — 3 tipos produzem system prompts distintos; `add_dir` é propagado quando há project_context
- `Report.format/1` — com project_context imprime header; sem, omite
- `CLI` — all-or-none; erro pra tipo inválido; erro pra Anthropic + project

### Functional

- One-shot CLI com Mock LLM (bug_fix): roda pipeline, imprime relatório com header, sai com status 0
- One-shot com path inexistente → erro + exit code != 0
- One-shot com 2 das 3 flags → erro "all-or-none"
- Orchestrator + project_context: verifica que os 3 agentes recebem o mesmo context e o Report final preserva project_context

## Arquivos a modificar

- `lib/trivium/types.ex` — +ProjectContext, +campo em Result
- `lib/trivium/llm/claude_cli.ex` — build_args estendido
- `lib/trivium/agents/idea_writer.ex` — prompts por tipo, propaga context
- `lib/trivium/agents/technical_researcher.ex` — idem
- `lib/trivium/agents/qa.ex` — idem
- `lib/trivium/orchestrator.ex` — propaga project_context
- `lib/trivium/report.ex` — header quando context presente
- `lib/trivium/cli.ex` — novas flags + lógica de despacho
- `README.md` — seção "Project mode"

## Verificação

1. `docker compose run --rm test` — suite deve crescer para ~140 tests, 0 falhas.
2. Smoke manual: criar um projeto dummy, rodar `./trivium --path /tmp/dummy --type bug --task "função X retorna nil"` com backend ClaudeCLI; confirmar que agentes leem arquivos do dummy.
3. Verificar que REPL sem flags continua funcionando como antes (regressão).
4. Verificar erro claro ao rodar `--path X --type bug` (sem `--task`).

## Fora de escopo

- Support pra tool use em `LLM.Anthropic` (v2)
- Project mode interativo no REPL (v2)
- Tipos adicionais além de bug/feature/analysis (ex: refactor, perf) — cobertos pelo "custom" se user usar `--type feature` genericamente
- Persistência do relatório em arquivo (v2)
- Integração nativa com claude-code como slash-command (v2 — o design one-shot atual já viabiliza)
