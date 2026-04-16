/**
 * Example: invoke the TAB plugin headlessly from a TypeScript script.
 *
 * Uses `@anthropic-ai/claude-agent-sdk` (the official TS Agent SDK).
 *
 * Prerequisites:
 *
 *     npm install @anthropic-ai/claude-agent-sdk
 *     # The TAB plugin must be installed in the host:
 *     #   claude plugin marketplace add lucascouts/tech-advisory-board
 *     #   claude plugin install tech-advisory-board@tech-advisory-board
 *
 * Environment:
 *
 *     ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN must be set.
 *
 * Usage:
 *
 *     npx tsx headless-typescript.ts "Which database for 1M IoT events/s?"
 */

import { query } from "@anthropic-ai/claude-agent-sdk";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

async function main(question: string): Promise<number> {
  let blockedReason: string | null = null;

  for await (const message of query({
    prompt: `/tech-advisory-board:tab "${question}"`,
    options: {
      allowedTools: [
        "WebSearch",
        "WebFetch",
        "Read",
        "Grep",
        "Glob",
        "Agent",
        "TodoWrite",
      ],
      permissionMode: "acceptEdits",
    },
  })) {
    if (message.type === "assistant") {
      for (const block of message.message.content ?? []) {
        if (block.type === "text") process.stdout.write(block.text);
      }
    } else if (message.type === "tool_use") {
      process.stderr.write(`\n[tool] ${message.name}`);
    } else if (message.type === "system" && message.subtype === "hook_block") {
      blockedReason = message.reason ?? "(no reason)";
      process.stderr.write(`\n[STOP GATE BLOCKED] ${blockedReason}`);
    }
  }

  if (blockedReason) return 1;

  const sessionsDir = "TAB/sessions";
  let synthPath: string | null = null;
  let newest = 0;
  try {
    for (const entry of readdirSync(sessionsDir)) {
      if (entry === "archived") continue;
      const candidate = join(sessionsDir, entry, "synthesis.json");
      try {
        const st = statSync(candidate);
        if (st.mtimeMs > newest) {
          newest = st.mtimeMs;
          synthPath = candidate;
        }
      } catch {
        /* skip sessions without a synthesis */
      }
    }
  } catch {
    console.error("No TAB/sessions directory — synthesis not produced.");
    return 1;
  }

  if (!synthPath) {
    console.error("No synthesis.json found.");
    return 1;
  }

  const synth = JSON.parse(readFileSync(synthPath, "utf8"));
  const rec = synth.recommendation?.primary ?? {};
  console.log("\n--- Recommendation ---");
  console.log(`Stack     : ${rec.stack}`);
  console.log(`Confidence: ${rec.confidence}`);
  console.log(`Rationale : ${(rec.rationale ?? "").slice(0, 500)}`);
  return 0;
}

const question = process.argv[2];
if (!question) {
  console.error('Usage: headless-typescript.ts "<question>"');
  process.exit(2);
}
main(question).then((code) => process.exit(code));
