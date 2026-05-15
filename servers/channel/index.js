#!/usr/bin/env node
/*
 * channel — MCP stdio server (zero deps, JSON-RPC 2.0 over stdin/stdout).
 *
 * ENV_SCRUB interaction (item 07):
 *   When CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 is active, the env vars
 *   below are stripped from this subprocess and sendMessage degrades
 *   silently (returns ok=false, degraded=true). See
 *   docs/TROUBLESHOOTING.md → "`channel` push is not sending messages".
 *
 * Env vars (either legacy or userConfig-injected form is accepted):
 *   - TELEGRAM_BOT_TOKEN     / CLAUDE_PLUGIN_OPTION_telegram_bot_token
 *   - TELEGRAM_CHAT_ID       / CLAUDE_PLUGIN_OPTION_telegram_chat_id
 *   - CHANNEL_WEBHOOK_URL    / CLAUDE_PLUGIN_OPTION_channel_webhook_url
 *   - CLAUDE_CODE_REMOTE_SESSION_ID         (item 21 — adds deep-link)
 *
 * Tool exposed:
 *   sendMessage(text: string, severity?: "info"|"warn"|"critical", deepLink?: string)
 *
 * Self-test:
 *   node index.js --test
 */

import { stdin, stdout, stderr, env, exit, argv } from "node:process";
import { request as httpsRequest } from "node:https";
import { request as httpRequest } from "node:http";
import { URL } from "node:url";

const PROTOCOL_VERSION = "2025-06-18";
const SERVER_NAME = "channel";
const SERVER_VERSION = "0.1.3";

const SEVERITY_VALUES = ["info", "warn", "critical"];

const TOOL_DEFINITIONS = [
  {
    name: "sendMessage",
    description:
      "Send a message to the configured push channel (Telegram and/or webhook). Degrades silently when env vars are absent or under CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1.",
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string", minLength: 1 },
        severity: { type: "string", enum: SEVERITY_VALUES },
        deepLink: { type: "string" },
      },
      required: ["text"],
      additionalProperties: false,
    },
  },
];

function logStderr(line) {
  try {
    stderr.write(`[channel] ${line}\n`);
  } catch {
    /* stderr unavailable; nothing useful to do */
  }
}

function postJson(url, payload) {
  return new Promise((resolve) => {
    let parsed;
    try {
      parsed = new URL(url);
    } catch (err) {
      resolve({ ok: false, status: 0, error: `invalid_url: ${err.message}` });
      return;
    }
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
      resolve({ ok: false, status: 0, error: "unsupported_protocol" });
      return;
    }
    const body = Buffer.from(JSON.stringify(payload), "utf8");
    const opts = {
      method: "POST",
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === "https:" ? 443 : 80),
      path: `${parsed.pathname || "/"}${parsed.search || ""}`,
      headers: {
        "content-type": "application/json",
        "content-length": body.length,
      },
      timeout: 5000,
    };
    const req = parsed.protocol === "https:" ? httpsRequest : httpRequest;
    const r = req(opts, (res) => {
      let data = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => {
        data += chunk;
      });
      res.on("end", () => {
        const status = res.statusCode || 0;
        resolve({ ok: status >= 200 && status < 300, status, body: data });
      });
    });
    r.on("timeout", () => {
      r.destroy(new Error("timeout"));
    });
    r.on("error", (err) => {
      resolve({ ok: false, status: 0, error: err.message });
    });
    r.write(body);
    r.end();
  });
}

function buildDeepLink(explicit) {
  if (typeof explicit === "string" && explicit.length > 0) return explicit;
  const remoteId = env.CLAUDE_CODE_REMOTE_SESSION_ID;
  if (remoteId && /^[A-Za-z0-9_-]+$/.test(remoteId)) {
    return `https://claude.ai/code/${remoteId}`;
  }
  return null;
}

function escapeMarkdown(text) {
  return String(text).replace(/[_*[\]()~`>#+\-=|{}.!]/g, (c) => `\\${c}`);
}

async function sendTelegram(text, severity, deepLink) {
  const token = env.TELEGRAM_BOT_TOKEN || env.CLAUDE_PLUGIN_OPTION_telegram_bot_token;
  const chatId = env.TELEGRAM_CHAT_ID || env.CLAUDE_PLUGIN_OPTION_telegram_chat_id;
  if (!token || !chatId) return { transport: "telegram", skipped: true, reason: "env_missing" };
  const prefix = severity ? `[${severity.toUpperCase()}] ` : "";
  const safe = escapeMarkdown(`${prefix}${text}`);
  const linkSuffix = deepLink ? `\n\n[session](${deepLink})` : "";
  const url = `https://api.telegram.org/bot${encodeURIComponent(token)}/sendMessage`;
  const payload = {
    chat_id: chatId,
    text: `${safe}${linkSuffix}`,
    parse_mode: "MarkdownV2",
    disable_web_page_preview: true,
  };
  const res = await postJson(url, payload);
  return { transport: "telegram", ok: res.ok, status: res.status, error: res.error };
}

async function sendWebhook(text, severity, deepLink) {
  const url = env.CHANNEL_WEBHOOK_URL || env.CLAUDE_PLUGIN_OPTION_channel_webhook_url;
  if (!url) return { transport: "webhook", skipped: true, reason: "env_missing" };
  const payload = {
    source: "channel",
    severity: severity || "info",
    text,
    deep_link: deepLink || null,
    sent_at: new Date().toISOString(),
  };
  const res = await postJson(url, payload);
  return { transport: "webhook", ok: res.ok, status: res.status, error: res.error };
}

async function sendMessage(args) {
  const text = typeof args?.text === "string" ? args.text.trim() : "";
  if (!text) {
    return { ok: false, degraded: false, error: "text_required", transports: [] };
  }
  const severity = SEVERITY_VALUES.includes(args?.severity) ? args.severity : "info";
  const deepLink = buildDeepLink(args?.deepLink);

  const results = await Promise.all([
    sendTelegram(text, severity, deepLink),
    sendWebhook(text, severity, deepLink),
  ]);

  const active = results.filter((r) => !r.skipped);
  const anyOk = active.some((r) => r.ok);
  const allEnvMissing = active.length === 0;

  if (allEnvMissing) {
    logStderr("degraded mode: no transport env vars present (TELEGRAM_* / CHANNEL_WEBHOOK_URL)");
  }

  return {
    ok: anyOk,
    degraded: allEnvMissing,
    deepLink: deepLink || null,
    transports: results,
  };
}

/* ---------- MCP JSON-RPC dispatch ---------- */

function rpcResult(id, result) {
  return JSON.stringify({ jsonrpc: "2.0", id, result });
}
function rpcError(id, code, message, data) {
  return JSON.stringify({
    jsonrpc: "2.0",
    id,
    error: { code, message, ...(data ? { data } : {}) },
  });
}

async function handleRequest(msg) {
  const { id, method, params } = msg;
  switch (method) {
    case "initialize":
      return rpcResult(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      });
    case "tools/list":
      return rpcResult(id, { tools: TOOL_DEFINITIONS });
    case "tools/call": {
      const name = params?.name;
      const args = params?.arguments || {};
      if (name !== "sendMessage") {
        return rpcError(id, -32601, `unknown_tool: ${name}`);
      }
      try {
        const result = await sendMessage(args);
        return rpcResult(id, {
          content: [{ type: "text", text: JSON.stringify(result) }],
          isError: !result.ok && !result.degraded,
        });
      } catch (err) {
        return rpcError(id, -32000, "tool_call_failed", { message: err.message });
      }
    }
    case "ping":
      return rpcResult(id, {});
    case "notifications/initialized":
    case "notifications/cancelled":
      return null;
    default:
      if (typeof id === "undefined") return null; // notification
      return rpcError(id, -32601, `method_not_found: ${method}`);
  }
}

function startStdioLoop() {
  let buffer = "";
  stdin.setEncoding("utf8");
  stdin.on("data", async (chunk) => {
    buffer += chunk;
    let nl;
    while ((nl = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        const out = rpcError(null, -32700, "parse_error");
        stdout.write(out + "\n");
        continue;
      }
      const out = await handleRequest(msg);
      if (out !== null) stdout.write(out + "\n");
    }
  });
  stdin.on("end", () => exit(0));
}

async function selfTest() {
  const calls = [
    { id: 1, method: "initialize", params: {} },
    { id: 2, method: "tools/list", params: {} },
    {
      id: 3,
      method: "tools/call",
      params: { name: "sendMessage", arguments: { text: "self-test ping", severity: "info" } },
    },
  ];
  for (const c of calls) {
    const out = await handleRequest({ jsonrpc: "2.0", ...c });
    stdout.write(out + "\n");
  }
}

if (argv.includes("--test")) {
  selfTest().then(() => exit(0));
} else {
  startStdioLoop();
}
