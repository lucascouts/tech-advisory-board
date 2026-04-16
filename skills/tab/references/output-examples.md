---
version: 4.0
last_updated: 2026-04-08
---

# Output Examples per Phase

Reference examples at target word budgets.
Scenario: "Backend framework for REST API with real-time notifications" — Standard mode, 3 technologies.

---

## Researcher Output (~500 words per tech)

```markdown
### FastAPI — Research Report

**Version & Release**
- Current version: 0.115.12 (released 2026-03-28)
- Release cycle: Patch every 2-3 weeks

**Community & Ecosystem**
- GitHub stars: 82K+ | Active contributors (90d): 95
- Ecosystem packages: 2,800+ PyPI

**Security**
- Recent CVEs: None. Starlette had CVE-2025-43859 (patched)

**Relevant Benchmarks**
- JSON: 18,200 req/s [TechEmpower R23]
- WebSocket: 12,500 concurrent [single source]

**License:** MIT — no changes

**Red Flags**
- Single maintainer (tiangolo) — bus factor 1

**Unverified Data**
- WebSocket throughput (single source)
```

---

## Landscape Scout Output (~200 words)

```markdown
**Atlas (Landscape Scout):**

**Shortlist -> Champions:**
| Alternative | Language | Version | Stage Fit | Rationale |
|---|---|---|---|---|
| FastAPI | Python | 0.115.12 | POC-Full | Async-native, WebSocket built-in |
| NestJS | TypeScript | 11.1 | MVP-Full | Enterprise patterns, Socket.io |
| Phoenix | Elixir | 1.7.21 | MVP-Full | Channels, battle-tested concurrency |

**Discard Table:**
| Tool | Reason for Exclusion |
|---|---|
| Django | Not async-first for real-time |
| Spring Boot | Overengineered for team of 3 |
| Gin (Go) | Team has no Go experience |

Complexity: **Moderate** -> **Standard** mode.
Estimated: ~7 subagents, 30-60K tokens, 5-12 min. Proceed?
```

---

## Champion Output (~600 words)

```markdown
**Dr. Marcus Chen (FastAPI Champion):**

### 1. Proposal & Toolchain
Python 3.13 + FastAPI 0.115.12 + SQLAlchemy 2.0.37 + asyncpg 0.30 +
WebSockets 14.2 + Celery 5.4 + Redis 5.2.

### 2. Top 3 Strengths
1. **Fastest Python framework**: 18,200 req/s. Async-native means
   notifications share the event loop — no separate process.
2. **Type-safe by design**: Pydantic v2 + auto-generated OpenAPI docs.
   Frontend team gets a live contract from day one.
3. **WebSocket as first-class citizen**: Raw WS, no protocol overhead.
   12,500 concurrent connections on 4-core VM [single source].

### 3. Top 3 Weaknesses & Mitigations
1. **Bus factor 1**: tiangolo is sole maintainer. Mitigation — built on
   Starlette/Pydantic with independent teams; fork risk is low.
2. **No built-in background tasks at scale**: Mitigation — Celery + Redis.
3. **Fragmented ORM story**: Mitigation — repository pattern from day one.

### 4. Vision by Stage
- **[POC]:** `uv add fastapi uvicorn` + SQLite. Ship in 1 week.
- **[MVP]:** Postgres + asyncpg, Celery for fanout, Redis pub/sub. 2-3 days migration.
- **[Full]:** Kubernetes, Redis Cluster, pgbouncer. $200-400/mo for 10K users.
```

---

## Vanguard Section (~200 extra words)

```markdown
### 5. Readiness Assessment (Vanguard)
- **Maturity:** Production-ready. 10+ years of Erlang/OTP heritage.
- **Production case studies:** Discord (5M+ concurrent), Bleacher Report (8M).
- **Breaking changes:** Phoenix 1.7->1.8 was non-breaking. Stable cycle.
- **Bus factor:** Core team of 6+, backed by DockYard and community.
- **Gaps vs established:** Fewer IDE tools, smaller Stack Overflow presence,
  debugging BEAM processes requires learning observer/recon.
```

---

## Cross-Examination Output (~300 words per champion)

```markdown
**Dr. Marcus Chen (FastAPI) -> attacks:**

### Direct Attacks
**To NestJS:** Socket.io adds 45KB client + proprietary protocol. For
one-directional push notifications, raw WebSocket with 3-line reconnect
is simpler and 2x lighter.

**To Phoenix:** 2M connections is WhatsApp/Erlang scale. Team has zero
Elixir experience — "2-4 weeks to learn" ignores OTP, pattern matching,
BEAM deployment. That's 2-4 months of reduced velocity.

### Counter-Defenses
"No built-in structure" is a feature. Cookiecutter templates + linting
provide exactly the needed structure without framework lock-in.

### Honest Concessions
Phoenix genuinely wins on raw WebSocket concurrency. At 100K+
simultaneous connections, the BEAM advantage becomes material.
```

---

## Advisor Output (~400 words)

```markdown
**Sarah Kim (Performance Advisor)**

**Declared bias:** Favors low-latency architectures.
**Declared blind spot:** May overweight benchmarks vs DX.
**Dimension:** Performance & Scalability

#### Evaluations

**FastAPI:** Async-native, 18,200 req/s. WebSocket lightweight. GIL limits
CPU-bound work. No data for >10K concurrent WS in cross-exam.
**Score: 7/10**

**NestJS:** V8 event loop handles I/O well. Socket.io adds ~15ms overhead
but reconnection logic is valuable for mobile. Scales via cluster.
**Score: 7/10**

**[VANGUARD] Phoenix:** BEAM is purpose-built for concurrency. 2M+
connections confirmed. Different league for real-time. Hiring 5-10x harder.
**Score: 8/10**

#### Verdict
Phoenix wins on raw real-time. FastAPI/NestJS comparable at <10K concurrent.

#### Direct challenge
**To FastAPI:** At what connection count does the GIL become the bottleneck?

#### Data verified
- FastAPI 18,200 req/s: Confirmed [TechEmpower R23]
- Phoenix 2M connections: Confirmed [Phoenix blog]
```

---

## Synthesis Output (Standard mode, ~1,200 words)

```markdown
## Consolidated Advisor Score Matrix

| Dimension | FastAPI | NestJS | Phoenix |
|-----------|---------|--------|---------|
| Performance (Sarah) | 7 | 7 | **8** |
| DX & Ecosystem (James) | **9** | 8 | 5 |
| Pragmatism (Ana) | **8** | 8 | 4 |
| **Average** | **8.0** | **7.7** | **5.7** |

**Divergence:** Phoenix scores 4-8 (delta=4) — excels technically
but carries adoption risk. FastAPI/NestJS consistent (delta=2, delta=1).

## Recommendation & Evolution
**Primary:** FastAPI — best balance of DX, performance, and pragmatism.
**Runner-up:** NestJS — if team prefers TypeScript or expects >10 devs.
**Vanguard:** Phoenix — only if real-time is THE core differentiator
and team commits to Elixir long-term.

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| FastAPI maintainer abandonment | Low | Medium | Built on Starlette/Pydantic |
| GIL bottleneck at scale | Medium | High | Celery workers for CPU tasks |
| NestJS learning curve delays MVP | Low | Medium | 2-week onboarding plan |

## Decision Record (ADR)
**Context:** REST API with real-time notifications, team of 3, MVP in 3 months.
**Decision:** FastAPI with WebSocket + Celery + Redis.
**Consequences:** Fast POC, Python ecosystem access, GIL ceiling at ~15K concurrent.
**Review trigger:** If concurrent connections exceed 10K sustained.

## Direct Recommendation
If I were building this project with your constraints, I'd go with FastAPI.
Setup: `uv init && uv add fastapi uvicorn sqlalchemy celery redis`.
Reversibility: High — FastAPI's thin abstraction makes migration straightforward.
```
