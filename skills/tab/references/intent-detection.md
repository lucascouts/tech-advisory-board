---
version: 1.0
---

# Intent Detection Protocol

When the user invokes the skill with arguments (e.g., `/tab "text"`), process
the argument immediately using this protocol.

---

## Step 1: Detect Intent Category

Intent detection is **semantic, not keyword-based**. Classify the user's intent
by meaning, regardless of language. The agent understands intent in any language.

| Intent | Semantic Pattern | TAB Behavior |
|--------|-----------------|--------------|
| **Analyze** | User references existing code/project/architecture and asks for evaluation, review, or assessment | **Evaluation mode** — Skip Champions, use Advisors to evaluate existing code/architecture. Synthesis = strengths, risks, improvement recommendations |
| **Improve** | User has existing code/project and wants to make it better (refactor, optimize, modernize, fix issues) | **Improvement mode** — Analyze current state first, then Champions propose improvement strategies. Synthesis = current issues + recommended changes + migration path |
| **Create** | User describes a new project/product to build from scratch (greenfield) | **Standard mode** — Full TAB flow for greenfield decisions. Context extraction focuses on vision, constraints, team |
| **Continue** | User has an existing project and wants to evolve, scale, grow, or move to next stage | **Evolution mode** — Auto-detect current stack, then Champions propose evolution paths. Synthesis = current state + next stage + migration |

---

## Step 2: Resolve Target

If the argument references a **file, folder, or project path**:
1. Check if the path exists (relative to cwd or absolute)
2. If it's a **file**: Read it and use its contents as context
3. If it's a **folder**: Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/extract-context.sh <path>` to get stack context, then read key files (manifests, configs, entry points)
4. If it's a **URL**: Note it for research phase

If the argument is **descriptive text** (not a path):
- Use it directly as the user's initial context for the session
- Skip context extraction questions that the text already answers

---

## Step 3: Adapt Session Flow

Based on the detected intent, the Moderator adapts:

- **Analyze/Improve with existing code**: Auto-detect context is critical. Read the actual code before any analysis. The Moderator announces what was detected and what the board will focus on.
- **Create (greenfield)**: Standard flow, but the argument pre-fills the "what is being built" question. Jump to remaining context extraction gaps.
- **Continue/Evolve**: Current stack is auto-detected. Context extraction focuses on: what changed, what's the next goal, what are the pain points.

---

## Example Invocations

These examples show various languages — intent detection works in any language:

```
/tab "analyze this project and tell me what to improve"
-> Intent: Analyze -> Reads project -> Advisors evaluate -> Improvement recommendations

/tab "I want to create a task management SaaS for small businesses"
-> Intent: Create -> Pre-fills context -> Standard TAB flow

/tab "let's improve the architecture of this project, it's getting hard to maintain"
-> Intent: Improve -> Auto-detects stack -> Champions propose refactoring strategies

/tab "./src/api"
-> Intent: Analyze (path detected) -> Reads folder structure -> Advisors evaluate architecture

/tab "I want to evolve this MVP to production"
-> Intent: Continue -> Auto-detects current state -> Champions propose evolution paths
```

If no argument is provided, proceed with standard context extraction.
