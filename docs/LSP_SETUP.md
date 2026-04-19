# LSP Setup for TAB

TAB ships a plugin-level `.lsp.json` that declares two Language Server
Protocol servers for structural code analysis during **Analyze** and
**Evolve** intents:

| Server | Languages | Binary |
|---|---|---|
| `pyright` | `.py`, `.pyi` | `pyright-langserver` |
| `typescript` | `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs` | `typescript-language-server` |

The binaries are **not bundled** with the plugin. Install them once per
host and the Claude Code LSP tool picks up TAB's `.lsp.json`
automatically.

## Installing

```bash
# Both servers in one go (Node ≥ 18 required)
npm install -g pyright typescript typescript-language-server
```

Verify:

```bash
pyright-langserver --help              # should print version + usage
typescript-language-server --version   # should print a version tag
```

## What the plugin uses LSP for

- **Analyze intent** (`/tech-advisory-board:tab "analise este projeto"`):
  the Moderator calls `LSP.find_references` and `LSP.get_hover` on
  detected entry points to map the architecture without re-reading
  every file with `Read`. Cheaper and structurally accurate.
- **Evolve intent**: the same lookups surface call graphs and type
  surfaces that feed the `migration_path[]` reasoning.
- **Auditor spot-checks**: when a claim references a specific TypeScript
  type or Python class, the auditor verifies the symbol exists and
  matches the claimed shape.

## Degraded behaviour

If the binaries are missing, Claude Code logs
`Executable not found in $PATH` for that server and **falls back to
`Read` + `Grep`**. The plugin still runs — analysis quality drops for
intents that would have benefited from LSP, but no session aborts on
absence.

## Why not declare LSP as a hard dependency?

TAB is intended to work on fresh CI runners, minimal container images
(alpine, distroless), and Bedrock / Vertex deployments where installing
Node packages is either slow or policy-restricted. LSP is an
**optional accelerator**, not a prerequisite. The `.lsp.json` is
preserved so that hosts which *do* have the binaries pick them up with
zero extra configuration.

## Related

- `.lsp.json` — plugin-level LSP declaration (loaded by Claude Code).
- `skills/tab/references/automation.md` §1.1 — LSP in the headless
  allow-list.
- `skills/tab/SKILL.md` Phase 0 — when Analyze intent prefers LSP over
  Read/Grep.
