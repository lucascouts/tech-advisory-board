# Permission Policy for TAB

This document lists every Bash / Agent / Tool invocation TAB emits and
recommends a permission policy (read-only vs mutating). It is designed to
be dropped into `.claude/settings.local.json` or a managed drop-in under
`managed-settings.d/`.

## 1. Read-only (safe to auto-allow)

These commands never mutate the filesystem or external state. Auto-allow
in both interactive and headless modes.

| Invocation | Purpose |
|---|---|
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-check-mcps)` | Inspect `~/.claude/settings.json` for MCP availability |
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-compute-cost --from-telemetry *)` | Roll up `telemetry.json` into a cost estimate (no writes) |
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-vanguard-timeline get *)` | Query the cross-project maturity ledger |
| `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/validate-synthesis*.sh *)` | Validate an existing synthesis — read only |
| `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/validate-claims.sh *)` | Validate claim hygiene — read only |
| `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh)` | Compute effective TAB config (prints JSON) |
| `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/extract-context.sh *)` | Extract stack context from the working directory |

Policy block (`.claude/settings.local.json`):

```json
{
  "permissions": {
    "allow": [
      "Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-check-mcps)",
      "Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-compute-cost --from-telemetry *)",
      "Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-vanguard-timeline get *)",
      "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/validate-synthesis*.sh *)",
      "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/validate-claims.sh *)",
      "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh)",
      "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/extract-context.sh *)"
    ]
  }
}
```

Classifier note (Claude Code ≥ v2.1.111): these invocations are also
classified `read-only` by the auto-mode classifier, so they do not trigger
a permission prompt even without an explicit allow entry. The explicit
allow is belt-and-suspenders for hosts with a stricter classifier.

## 2. Mutating — require confirmation

These commands write ADRs, append to the index, or touch the cross-project
ledger. Default policy is **ask**; in CI, use `"defer"` in a scoped
`PreToolUse` hook (see `skills/tab/references/automation.md` §7.2).

| Invocation | Purpose |
|---|---|
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-new-adr *)` | Generate a new MADR ADR |
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-supersede-adr *)` | Link ADRs, rewrite status lines, update index |
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-vanguard-timeline append *)` | Append to maturity ledger |
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-schedule-rechallenge *)` | Register a cron trigger for rechallenge |
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-init-dir)` | First-time TAB workspace scaffolding |
| `Bash(${CLAUDE_PLUGIN_ROOT}/bin/tab-resume-session)` | Mutates `TAB/state/*.resume` markers |

## 3. Hard-deny for auto-mode

The plugin never needs these; deny outright to surface accidental misuse
of the bin tools under `sudo` or against `/etc/`:

```json
{
  "permissions": {
    "deny": [
      "Bash(sudo *)",
      "Bash(* /etc/* *)",
      "Bash(rm -rf /*)"
    ]
  }
}
```

## 4. Observability

When the auto-mode classifier denies one of TAB's tool calls, the host
fires `PermissionDenied` (Claude Code ≥ v2.1.89). A future iteration of
this plugin may record those denials into `telemetry.json` so that
advisors can be re-configured when CI policies tighten.

## 5. Related

- `skills/tab/references/automation.md` §1.1 — minimum allow-list for headless
- `skills/tab/references/automation.md` §7.2 — PreToolUse `"defer"` recipe
- `docs/MANAGED_SETTINGS.md` — org-level policy enforcement
