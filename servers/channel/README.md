# channel — MCP push-channel server

Plugin-bundled MCP stdio server. Routes Moderator/Notification messages
to a push channel (Telegram Bot API and/or generic webhook). Zero
runtime dependencies — pure Node.js stdlib.

## Tool

- `sendMessage(text: string, severity?: "info"|"warn"|"critical", deepLink?: string)`
  - Sends `text` to all configured transports concurrently.
  - Returns `{ ok, degraded, deepLink, transports: [...] }`.
  - `degraded: true` means **no** transport env vars were set; the call
    is a silent no-op (does not derail the caller).

## Env vars

| Variable | Required for | Notes |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Telegram | Bot API token |
| `TELEGRAM_CHAT_ID`   | Telegram | Chat / channel ID |
| `CHANNEL_WEBHOOK_URL` | Webhook | HTTPS POST endpoint accepting JSON |
| `CLAUDE_CODE_REMOTE_SESSION_ID` | Optional | If set, builds `https://claude.ai/code/<id>` deep-link |

When **all** transports are absent (no env vars), `sendMessage` returns
`degraded: true` and logs `[channel] degraded mode` to stderr.

## ENV_SCRUB caveat

Under `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` (Claude Code env hardening),
the env vars listed above are stripped from this subprocess and the
server falls back to degraded mode. See
[`docs/TROUBLESHOOTING.md`](../../docs/TROUBLESHOOTING.md) →
"`channel` push is not sending messages".

## Self-test

```bash
node servers/channel/index.js --test
```

Emits three JSON-RPC responses (`initialize`, `tools/list`,
`tools/call`) on stdout. With no env vars, `tools/call` returns
`degraded: true` and `ok: false` — both expected.

## MCP inspector

```bash
npx @modelcontextprotocol/inspector node servers/channel/index.js
```

Lists the `sendMessage` tool and lets you exercise it interactively.

## Plugin registration

Declared in `.claude-plugin/plugin.json` under `mcpServers`:

```json
{
  "mcpServers": {
    "channel": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/servers/channel/index.js"]
    }
  }
}
```

The exposed tool is then namespaced as
`mcp__channel__sendMessage` for hooks and agents.
