# Technical Advisory Board (TAB)

A Claude Code skill that convenes an expert advisory board to deliberate on technical decisions. Instead of a single opinion, you get structured debate between multiple specialists with different perspectives.

## What it does

When you ask a technical question like "what database should I use for my real-time app?" or "compare Next.js vs Remix for my use case", TAB assembles a virtual board of experts that:

1. **Extracts context** from your project and question
2. **Researches** current technology landscape using live web data
3. **Assigns Champions** to advocate for competing stacks
4. **Runs cross-examination** where champions challenge each other
5. **Deploys Domain Advisors** for independent scoring (security, scalability, DX, etc.)
6. **Synthesizes** a final recommendation with ADR-style documentation

## Complexity-adaptive modes

| Mode | Complexity | Champions | Advisors | Use case |
|------|-----------|-----------|----------|----------|
| Express | Trivial | 0 | 0 | Quick shortlist + recommendation |
| Quick | Simple | 2 | 2 | Focused comparison |
| Standard | Moderate | 3 | 3-4 | Full deliberation with cross-exam |
| Complete | High | 3-4 | 4-5 | Deep analysis with clarification rounds |
| Complete+ | Very High | 4-5 | 5-6 | Extended research, multiple cross-exam rounds |

## Installation

### As a project skill

Copy this directory into your project's `.claude/skills/` folder:

```bash
cp -r tech-advisory-board /path/to/your/project/.claude/skills/
```

### As a global skill

Copy to your Claude Code skills directory:

```bash
cp -r tech-advisory-board ~/.claude/skills/
```

## Usage

```
/tab what database should I use for a real-time collaborative editor?
/tab compare Rust vs Go for a CLI tool that processes large files
/tab help me plan the tech stack for a SaaS MVP
/tab is Svelte a good choice for a dashboard with complex data viz?
/tab analyze this project and suggest improvements
```

## Enhanced with MCP servers

TAB works standalone but benefits from these MCP servers for live research:

- **perplexity** - Web-grounded search and research
- **context7** - Up-to-date library documentation
- **brave-search** - Web search fallback

## Project structure

```
tech-advisory-board/
├── SKILL.md              # Skill definition & orchestration protocol
├── agents/               # Subagent templates
│   ├── tab-advisor.md    # Domain advisor (independent evaluator)
│   ├── tab-champion.md   # Stack champion (technology advocate)
│   └── tab-researcher.md # Research specialist
├── references/           # Protocol & process definitions
│   ├── archetypes.md     # 12 champion identity templates
│   ├── context-extraction.md
│   ├── debate-protocol.md
│   ├── intent-detection.md
│   ├── specialists.md    # 6 core advisors + 14 domain catalog
│   ├── stage-definitions.md
│   └── synthesis-template.md
├── scripts/              # Automation utilities
│   ├── extract-context.sh
│   └── validate-synthesis.sh
└── evals/                # Test suite (34 cases)
    ├── evals.json
    ├── README.md
    └── fixtures/
```

## License

MIT
