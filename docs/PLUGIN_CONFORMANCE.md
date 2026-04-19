# Plugin Conformance

> Registro de padrões do TAB que **são canônicos** conforme a documentação
> oficial do Claude Code. Este arquivo existe para evitar que revisões
> apressadas (humanas ou de subagentes) removam ou refatorem essas peças
> por engano — tratando-as como "não-padrão" quando na verdade seguem o
> caminho default definido em `/en/plugins-reference`, `/en/hooks`,
> `/en/sub-agents` e `/en/skills`.
>
> **Regra geral:** antes de remover ou "normalizar" qualquer um dos
> itens abaixo, abra a doc oficial correspondente. Se a doc contradizer
> o padrão atual, atualize **também** este documento no mesmo PR.

## 1. Padrões canônicos em uso

| # | Peça | Evidência no repo | Doc oficial | Por que é canônico |
|---|---|---|---|---|
| 1 | `hooks/hooks.json` na raiz do plugin | `hooks/hooks.json` | `/en/plugins-reference#hooks` | Caminho **default** para hook manifests de plugin. O host lê `hooks/hooks.json` automaticamente quando o plugin é ativado; nenhum campo adicional em `plugin.json` é necessário. |
| 2 | `tools:` / `disallowedTools:` em frontmatter de subagente | `agents/advisor.md:10,17`, `agents/auditor.md:14`, `agents/champion.md:10`, `agents/researcher.md:11,20`, `agents/supervisor.md:10,15` | `/en/sub-agents` | Plugin-shipped agents suportam allowlist (`tools`) e denylist (`disallowedTools`) declarativamente no frontmatter. Não requer config no host. |
| 3 | `.lsp.json` na raiz do plugin | `.lsp.json` (pyright + typescript-language-server) | `/en/plugins-reference` (LSP bundling) | Caminho **default** para LSP servers bundled pelo plugin. Ativados automaticamente quando o plugin é instalado e `node` está no `PATH`. |
| 4 | `memory: project` em frontmatter de subagente | `agents/auditor.md:11`, `agents/researcher.md:10` | `/en/sub-agents` | Campo documentado e suportado em subagentes plugin-shipped. Acumula notas por-projeto entre sessões. No TAB: `researcher` (cache de ecossistema) e `auditor` (histórico de auditorias). COI disclosure é obrigatória sempre que `memory: project` está ativo. |
| 5 | Skills com shell blocks `` !`…` `` em Markdown | `skills/tab/SKILL.md:52,58,60,62,64`, `skills/rechallenge/SKILL.md:67,83,85`, `skills/tab/references/persistence-protocol.md:31,43` | `/en/skills#inject-dynamic-context` | Pattern oficial "Inject dynamic context". Os blocos `` !`cmd` `` são executados pelo host e o stdout vira contexto injetado no skill body. Só é desabilitado por `disableSkillShellExecution: true` (default é `false` — ver `docs/TROUBLESHOOTING.md`). |

### Observação sobre o item 5

O uso de shell blocks em skills é **central** ao design do TAB: o
Moderator depende deles para injetar estado dinâmico (workspace init,
config merge, resume detection, contexto de projeto) no próprio skill
body. Remover esses blocos quebra o bootstrap das skills `tab` e
`rechallenge`. Se uma dependência de empresa exigir
`disableSkillShellExecution: true`, documente o workaround em
`docs/MANAGED_SETTINGS.md` — não edite os SKILL.md.

## 2. Peças genuinamente experimentais

Estes são os **únicos** pontos do TAB que dependem de features marcadas
como experimentais ou muito recentes pela própria documentação oficial.
Tudo o mais no plugin é canônico (ver §1).

| Peça | Natureza | Flag / versão mínima | Degradação |
|---|---|---|---|
| Agent Teams (`agent_team_mode=agent_teams`) | **Experimental** conforme `/en/agent-teams` | Requer `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. API pode mudar entre minor releases do Claude Code. | Default do plugin é `subagents` (fan-out simulado, estável). Modo `auto` prefere Agent Teams se o env var estiver setado e cai silenciosamente para `subagents` caso contrário. `SessionStart` emite warning se `agent_teams` for pinado sem o env var. Ver `skills/tab/references/agent-teams-mode.md`. |
| `model: claude-opus-4-7` + `effort: xhigh` | **Recente**, hoje estável | Claude Code ≥ v2.1.111 | Nenhuma — `effort: xhigh` é aceito na versão mínima declarada em `.claude-plugin/plugin.json`. Usado em `agents/auditor.md` e `agents/champion.md`. |

## 3. Quando este arquivo precisa mudar

- **Adicione uma linha em §1** quando introduzir um novo padrão canônico
  no TAB cuja evidência não seja óbvia a partir do código (ex.: um novo
  campo de frontmatter de skill/agent suportado pelo host).
- **Mova uma linha de §2 para §1** quando a feature sair de beta e a
  doc oficial remover o aviso de experimental.
- **Adicione uma linha em §2** somente se introduzir dependência nova em
  feature marcada como experimental, beta, ou deprecated-em-breve pela
  doc oficial.

Nunca remova uma linha sem citar no commit a URL da doc oficial que
deprecou o padrão.

## 4. Histórico da avaliação

A existência deste arquivo foi motivada pelo tópico 3 de
`ANALISE-CRITICA.md`, que registrou uma avaliação errada em que um
subagente explorador classificou peças canônicas como "não-padrão".
Este documento formaliza o registro para que futuras revisões não
repitam o equívoco.
