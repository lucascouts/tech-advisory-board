"""Example: invoke the TAB plugin headlessly from a Python script.

Uses the anthropic-sdk `claude-agent-sdk` package (the Python Agent SDK).

Prerequisites:

    pip install claude-agent-sdk
    # The TAB plugin must be installed in the host:
    #   claude plugin marketplace add lucascouts/tech-advisory-board
    #   claude plugin install tech-advisory-board@tech-advisory-board

Environment:

    ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN must be set.

What this script does:

    1. Kicks off a TAB session with a user-supplied question.
    2. Streams tool events so you can observe champions/advisors/auditor.
    3. Waits for Stop.
    4. Locates the newest synthesis.json and parses the recommendation.
    5. Fails (exit 1) if the Stop-gate emitted a block-reason.
"""

from __future__ import annotations

import asyncio
import json
import os
import pathlib
import sys

from claude_agent_sdk import query


async def run(question: str) -> int:
    blocked_reason: str | None = None

    async for message in query(
        prompt=f'/tech-advisory-board:tab "{question}"',
        options={
            # Allow the full set of tools TAB needs.
            "allowed_tools": [
                "WebSearch",
                "WebFetch",
                "Read",
                "Grep",
                "Glob",
                "Agent",
                "TodoWrite",
            ],
            # Let Claude accept the plugin's hook decisions as-is.
            "permission_mode": "acceptEdits",
        },
    ):
        # Surface subagent status-line events and hook blocks.
        mtype = message.get("type")
        if mtype == "assistant":
            for block in message.get("message", {}).get("content", []):
                if block.get("type") == "text":
                    sys.stdout.write(block["text"])
                    sys.stdout.flush()
        elif mtype == "tool_use":
            name = message.get("name", "?")
            print(f"\n[tool] {name}", file=sys.stderr)
        elif mtype == "system" and message.get("subtype") == "hook_block":
            blocked_reason = message.get("reason", "(no reason)")
            print(f"\n[STOP GATE BLOCKED] {blocked_reason}", file=sys.stderr)

    if blocked_reason:
        return 1

    # Locate newest synthesis.
    tab_sessions = pathlib.Path("TAB/sessions")
    if not tab_sessions.is_dir():
        print("No TAB/sessions directory — synthesis not produced.", file=sys.stderr)
        return 1

    candidates = sorted(
        (p for p in tab_sessions.glob("*/synthesis.json") if "archived" not in p.parts),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        print("No synthesis.json found.", file=sys.stderr)
        return 1

    synth = json.loads(candidates[0].read_text(encoding="utf-8"))
    rec = synth.get("recommendation", {}).get("primary", {})
    print("\n--- Recommendation ---")
    print(f"Stack     : {rec.get('stack')}")
    print(f"Confidence: {rec.get('confidence')}")
    print(f"Rationale : {rec.get('rationale', '')[:500]}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print('Usage: headless-python.py "<question>"', file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(asyncio.run(run(sys.argv[1])))
