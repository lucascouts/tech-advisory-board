# MCP Setup for TAB

The Technical Advisory Board plugin requires **three MCP capabilities** — web
search, library docs, and cross-validation search. It does **not** require any
specific vendor. The servers listed below are the author's preferences and ship
wired into the subagent `tools:` fields by default; any MCP that exposes an
equivalent capability is accepted. Claude Code plugin validators do not allow
plugins to declare `mcpServers` directly, so you install them once in the host
session and every TAB run picks them up automatically.

## Capability contract

| Capability | Used by | Default recommendation | Accepted alternatives |
|---|---|---|---|
| Web search | researcher, champion, advisor, auditor | `perplexity` | Tavily, Exa, Kagi, serpapi-mcp, any MCP exposing `web_search` |
| Library docs | researcher, champion, auditor | `context7` | any MCP exposing `query-docs` / `resolve-library-id` |
| CVE / security / cross-validation | researcher, auditor | `brave-search` | any MCP exposing `web_search` with independent index |

Substitute freely — as long as the capabilities are preserved, the plugin
operates identically. When swapping, edit `tools:` in the affected agent
frontmatter to match the new tool names, or alias them in your local `.mcp.json`.

## Why MCPs matter

| Without MCPs | With MCPs |
|---|---|
| `WebSearch` fallback only | vendor-specific research + docs + cross-validation tools |
| Claims flagged `[unverified]` in synthesis | Claims promoted to `[high-conf]` / `[med-conf]` with citations |
| Researcher subagent skips 2-source rule | 2-source rule enforced via `researcher.md:43-44` |
| Auditor `spot-check` phase is best-effort | Auditor runs reason-style + doc lookup per high-stake claim |

## Default recommendations

### 1. Perplexity (`perplexity_search`, `perplexity_research`, `perplexity_reason`, `perplexity_ask`)

Primary source for current ecosystem data, version releases, CVE disclosures, community signals. Perplexity `research` runs slow (30s+) but returns structured multi-source investigations used by the Auditor.

### 2. Context7 (`resolve-library-id`, `query-docs`)

Primary source for **library / framework / SDK documentation**. Queried by the Researcher for API syntax, version migration, setup instructions. Preferred over web search for library docs because it returns indexed, version-aware content.

### 3. Brave Search (`brave_web_search`, `brave_local_search`)

Secondary cross-validation source. Used for community signals, GitHub issue trends, and regional / non-English content where Perplexity may under-index.

## Installing the MCPs

MCP installation is host-specific. See the Claude Code MCP documentation for authoritative commands. Representative examples:

```bash
# Claude Code (user-scoped, all projects)
claude mcp add perplexity --env PERPLEXITY_API_KEY=sk-... -- npx -y perplexity-mcp-server
claude mcp add context7 -- npx -y @upstash/context7-mcp
claude mcp add brave-search --env BRAVE_API_KEY=... -- npx -y brave-search-mcp
```

Or add them to `~/.claude/settings.json` under the `mcpServers` key:

```json
{
  "mcpServers": {
    "perplexity": {
      "command": "npx",
      "args": ["-y", "perplexity-mcp-server"],
      "env": { "PERPLEXITY_API_KEY": "sk-..." }
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "brave-search": {
      "command": "npx",
      "args": ["-y", "brave-search-mcp"],
      "env": { "BRAVE_API_KEY": "..." }
    }
  }
}
```

API keys:

- **Perplexity**: https://www.perplexity.ai/settings/api
- **Brave Search**: https://api.search.brave.com/
- **Context7**: no key required (public service).

## Diagnostic

After installation, run:

```bash
check-mcps
```

This script inspects `~/.claude/settings.json` and `$CLAUDE_PROJECT_DIR/.claude/settings.json` and prints which recommended MCPs are configured, missing, or misconfigured. It makes no network calls and never mutates state. Alternative MCPs with equivalent capabilities are accepted — `check-mcps` only reports on the default trio, not on the plugin's correctness.

## Degraded mode

If MCPs remain unavailable:

- The Researcher subagent falls back to `WebSearch` + `WebFetch`.
- Claims are tagged `[unverified]` (see `skills/tab/references/confidence-tags.md`).
- The Auditor still runs but its spot-check phase is weaker.
- `validate-claims.sh` will emit warnings — not errors — for `[unverified]` claims.

The plugin remains usable in degraded mode. The synthesis will be honest about the reduced confidence.
