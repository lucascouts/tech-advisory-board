# Managed Settings for TAB

Organizations that roll out `tech-advisory-board` through the managed
plugin channel can enforce policy fragments without touching user-owned
settings. This document lists the knobs TAB respects and gives drop-in
examples for `managed-settings.d/`.

## 1. Where managed settings live

Claude Code ≥ v2.1.83 loads drop-ins from:

```
/etc/claude-code/managed-settings.d/*.json           # Linux
$ProgramData\ClaudeCode\managed-settings.d\*.json    # Windows
```

Files are merged alphabetically on top of the user's `~/.claude/settings.json`.
Plugins do not override managed settings — the managed layer always wins.

## 2. Disable auditor or supervisor at org level

```json
// 10-tab-disable-auditor.json
{
  "plugins": {
    "tech-advisory-board": {
      "userConfig": {
        "auditor_enabled": false,
        "supervisor_gate_enabled": false
      }
    }
  }
}
```

Effect: every TAB session inside the org skips the auditor and supervisor
gates, trading rigor for cost. The plugin writes
`auditor_override_reason: "managed-policy"` into `synthesis.json` so
downstream auditors know.

## 3. Pin cheaper models

```json
// 20-tab-model-budget.json
{
  "plugins": {
    "tech-advisory-board": {
      "userConfig": {
        "champion_model": "claude-sonnet-4-6",
        "auditor_model":  "claude-sonnet-4-6",
        "advisor_model":  "claude-sonnet-4-6"
      }
    }
  }
}
```

Effect: Champion / Auditor fall back to Sonnet. TAB still runs, but
adversarial rigor drops — recommended only for Express / Quick / Standard
sessions with a hard cost ceiling.

## 4. Cap spend

```json
// 30-tab-cost-cap.json
{
  "plugins": {
    "tech-advisory-board": {
      "userConfig": {
        "max_cost_per_session_usd": 2.00,
        "warn_at_usd": 1.50
      }
    }
  }
}
```

## 5. Force execution of plugin hooks

When deploying TAB to seats that disable user-defined hooks by default,
opt back in for managed plugins only (Claude Code ≥ v2.1.101):

```json
// 40-tab-hook-allowlist.json
{
  "hooks": {
    "allowManagedHooksOnly": true
  }
}
```

Effect: `PreCompact`, `StopFailure`, `TaskCreated`, `CwdChanged`,
`FileChanged`, and the rest of the TAB hooks execute even when the user's
`~/.claude/settings.json` globally sets `"hooks": false`. Only hooks that
ship from *managed* plugins are allowed under this setting — user-authored
hooks stay disabled.

## 6. Validation

Drop-ins are JSON; malformed files are ignored silently. Validate with:

```bash
jq . /etc/claude-code/managed-settings.d/*.json
```

After rolling out a policy change, verify it took effect by inspecting
the merged settings surface:

```bash
claude diag --show-settings | jq '.plugins."tech-advisory-board"'
```

## 7. Related

- `userConfig` schema: `.claude-plugin/plugin.json`
- Hook inventory: `hooks/hooks.json` and `skills/tab/references/hooks-catalog.md`
- Permission policy: `docs/PERMISSIONS.md`
