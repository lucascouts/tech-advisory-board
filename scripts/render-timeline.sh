#!/usr/bin/env bash
# render-timeline.sh — write the self-contained timeline HTML skeleton into
# a TAB session directory (§3.6 of APRIMORAMENTOS.md).
#
# Usage:
#   render-timeline.sh <session-dir>
#
# The generated timeline.html polls timeline-events.ndjson (written by
# monitor.sh) via fetch() on the local filesystem. Opens correctly from
# a `file://` URL, no server required.
#
# Run once at session creation; the HTML stays in place and re-reads the
# NDJSON tail every 1500ms as events accumulate.
set -uo pipefail

SESSION_DIR="${1:-}"
if [[ -z "$SESSION_DIR" || ! -d "$SESSION_DIR" ]]; then
    echo "Usage: render-timeline.sh <session-dir>" >&2
    exit 2
fi

OUT="$SESSION_DIR/timeline.html"

cat > "$OUT" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>TAB session timeline</title>
  <style>
    :root {
      --bg: #0f1115; --fg: #e7e9ee; --muted: #8b93a7;
      --ok: #5ec85e; --warn: #f5a524; --err: #f26969; --accent: #5b9dff;
      --row: rgba(255,255,255,0.04);
    }
    html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg);
                 font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    header { display: flex; gap: 1rem; align-items: baseline; padding: .75rem 1rem;
             border-bottom: 1px solid rgba(255,255,255,.08); }
    header h1 { font-size: 14px; font-weight: 600; margin: 0; letter-spacing: .02em; }
    header .meta { color: var(--muted); font-size: 12px; }
    main { display: grid; grid-template-columns: 2fr 1fr; gap: .5rem; padding: .5rem 1rem; }
    section { border: 1px solid rgba(255,255,255,.06); border-radius: 4px; padding: .5rem; }
    h2 { font-size: 12px; font-weight: 600; margin: 0 0 .5rem; color: var(--muted);
         letter-spacing: .06em; text-transform: uppercase; }
    .gantt { display: grid; grid-template-columns: 140px 1fr; gap: .25rem .5rem;
             align-items: center; font-size: 12px; }
    .gantt .lane-name { color: var(--muted); }
    .gantt .lane-track { position: relative; height: 14px; background: var(--row);
                         border-radius: 2px; overflow: hidden; }
    .gantt .bar { position: absolute; top: 0; bottom: 0; background: var(--accent);
                  border-radius: 2px; opacity: .85; }
    .gantt .bar.active { background: linear-gradient(90deg, var(--accent), #a88cff); }
    #claims { max-height: 500px; overflow-y: auto; }
    .claim { padding: .25rem 0; border-bottom: 1px dashed rgba(255,255,255,.05); }
    .claim .tag { display: inline-block; padding: 0 .3rem; border-radius: 2px;
                  font-size: 11px; margin-right: .4rem; color: #111; background: var(--ok); }
    .claim .tag.unverified { background: var(--warn); }
    footer { padding: .5rem 1rem; border-top: 1px solid rgba(255,255,255,.08);
             color: var(--muted); font-size: 12px; display: flex; justify-content: space-between; }
    .dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%;
           margin-right: .25rem; vertical-align: middle; }
    .dot.ok { background: var(--ok); } .dot.warn { background: var(--warn); }
    .dot.err { background: var(--err); }
  </style>
</head>
<body>
  <header>
    <h1 id="title">TAB session timeline</h1>
    <span class="meta" id="meta">loading…</span>
  </header>
  <main>
    <section>
      <h2>Phase / subagent Gantt</h2>
      <div class="gantt" id="gantt">(waiting for events)</div>
    </section>
    <section>
      <h2>Claims</h2>
      <div id="claims">(none yet)</div>
    </section>
  </main>
  <footer>
    <span id="status"><span class="dot ok"></span>connected · polling every 1.5s</span>
    <span id="cost">cost · $0.00</span>
  </footer>
<script>
(async () => {
  const params = new URLSearchParams(location.search);
  const NDJSON = params.get("events") || "timeline-events.ndjson";
  const POLL = 1500;

  const $ = (id) => document.getElementById(id);

  const state = {
    session_id: null, mode: null, phase: null, next_phase: null,
    cost: 0, max_cost: 5.0,
    lanes: new Map(),          // laneName → [{from, to|null, active}]
    claims: [],
    firstEventAt: null, lastEventAt: null,
  };

  async function fetchTail(offset) {
    try {
      const res = await fetch(NDJSON, {cache: "no-store"});
      if (!res.ok) return null;
      const txt = await res.text();
      const lines = txt.split("\n").filter(Boolean);
      return lines.slice(offset).map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
    } catch (e) { return null; }
  }

  function upsertLane(name, at, active) {
    if (!state.lanes.has(name)) state.lanes.set(name, []);
    const arr = state.lanes.get(name);
    const last = arr[arr.length - 1];
    if (active) {
      if (!last || last.to) arr.push({from: at, to: null, active: true});
    } else {
      if (last && last.to === null) { last.to = at; last.active = false; }
    }
  }

  function applyEvent(ev) {
    state.lastEventAt = ev.at;
    if (!state.firstEventAt) state.firstEventAt = ev.at;
    if (ev.session_id) state.session_id = ev.session_id;

    switch (ev.event) {
      case "session-activated":
        state.mode = ev.mode || state.mode;
        state.phase = ev.phase;
        upsertLane("session", ev.at, true);
        break;
      case "phase-advanced":
        state.phase = ev.to_phase;
        state.next_phase = ev.next_phase;
        upsertLane(ev.from_phase || "(phase)", ev.at, false);
        upsertLane(ev.to_phase || "(phase)", ev.at, true);
        break;
      case "subagent-started":
        upsertLane(`${ev.agent_type || "subagent"}:${(ev.agent_id||"").slice(0,6)}`, ev.at, true);
        break;
      case "subagent-returned":
        // without an agent_id we can only count; skip per-lane change
        break;
      case "budget-warn":
      case "budget-exceeded":
        state.cost = ev.cost_usd ?? state.cost;
        state.max_cost = ev.max_cost_usd ?? state.max_cost;
        break;
      case "snapshot":
        state.phase = ev.phase;
        state.next_phase = ev.next_phase;
        state.mode = ev.mode;
        state.cost = ev.cost_usd ?? state.cost;
        state.max_cost = ev.max_cost_usd ?? state.max_cost;
        break;
    }
  }

  function render() {
    $("title").textContent = `TAB · ${state.session_id || "?"}`;
    $("meta").textContent = `mode=${state.mode || "?"}  phase=${state.phase || "?"} → ${state.next_phase || "?"}`;
    $("cost").textContent = `cost · $${(state.cost).toFixed(2)} / $${state.max_cost.toFixed(2)}`;

    const gantt = $("gantt");
    gantt.innerHTML = "";
    if (state.lanes.size === 0) {
      gantt.textContent = "(waiting for events)";
      return;
    }
    const from = new Date(state.firstEventAt).getTime();
    const to   = new Date(state.lastEventAt  || Date.now()).getTime();
    const span = Math.max(1000, to - from);
    for (const [name, segments] of state.lanes) {
      const label = document.createElement("div");
      label.className = "lane-name";
      label.textContent = name;
      const track = document.createElement("div");
      track.className = "lane-track";
      for (const seg of segments) {
        const sStart = new Date(seg.from).getTime();
        const sEnd   = new Date(seg.to || Date.now()).getTime();
        const left  = ((sStart - from) / span) * 100;
        const width = Math.max(0.5, ((sEnd - sStart) / span) * 100);
        const bar = document.createElement("div");
        bar.className = "bar" + (seg.active ? " active" : "");
        bar.style.left = `${left}%`;
        bar.style.width = `${width}%`;
        track.appendChild(bar);
      }
      gantt.appendChild(label);
      gantt.appendChild(track);
    }
  }

  let offset = 0;
  async function tick() {
    const events = await fetchTail(offset);
    if (events && events.length) {
      offset += events.length;
      for (const ev of events) applyEvent(ev);
      render();
    } else if (events === null) {
      $("status").innerHTML = `<span class="dot warn"></span>NDJSON not readable — open this HTML from the session directory`;
    }
  }
  tick();
  setInterval(tick, POLL);
})();
</script>
</body>
</html>
HTML

printf '%s\n' "$OUT"
