# SKY — Architecture

**Version:** v1.2 · Phase 0
**Canonical diagram:** [`diagrams/system.txt`](diagrams/system.txt)

---

## 1. The governing principle

> **The Mac Pro orchestrates. It does not render, and it does not reason.**

Everything below follows from that sentence and from the hardware that forced it.

---

## 2. The constraint that shaped everything

| Component | 2013 Mac Pro reality | Consequence |
|---|---|---|
| GPU | Dual AMD FirePro D300/D500/D700 | No CUDA. No practical ROCm for this generation. Local inference is a dead end (Risk #14). |
| CPU | Xeon E5 v2, **no AVX2** | CPU inference is also handicapped. Whisper needs benchmarking, with cloud STT as the fallback (Risk #13). |
| RAM / storage | Plentiful, fast PCIe blade SSD | Postgres, pgvector, and container orchestration are entirely comfortable. |
| Thermals | Single-fan cylinder, burst-oriented | Sustained 24/7 load needs monitoring (Risk #7). |

Read that table as a spec rather than a complaint and the architecture writes itself: **put each kind of work where it can actually run.**

| Concern | Location | Why |
|---|---|---|
| Reasoning | Cloud LLM APIs, behind a router | The box cannot do it. See DL-002. |
| Rendering | Client browser, WebGL | The server draws zero frames. Every client already has a GPU. |
| Speech | Local first, cloud fallback | Benchmark before committing (Risk #13). |
| Retrieval | Local Postgres + pgvector | Cheap, private, fast enough at this scale. |
| Orchestration | Local FastAPI + Docker | Exactly what this hardware is good at. |
| Secrets | Local, isolated, never in context | Security boundary. See DL-003. |

---

## 3. Components

### `sky-gateway` — the front door

FastAPI. Owns sessions, WebSocket transport, streaming, and **cancellation**.

Cancel is not a feature added later. An assistant you cannot interrupt is an assistant you stop using, and retrofitting interruption into a streaming pipeline that never had it is genuinely painful. The frame protocol carries it from Phase 0, even though Phase 0 only echoes.

Also owns instrumentation: **time-to-first-token** and the **cost ledger**. Both exist before there is anything to measure, because measuring after the fact means guessing.

### `sky-core` — the orchestrator *(Phase 1)*

LiteLLM router, tool dispatcher, persona layer, and the **permission broker**. The broker is the component that makes DL-003 real: tools declare a tier and an operation, and the broker decides whether the call proceeds, requires approval, or is refused. It ships in Phase 1 with a single registered tool, purely so that no tool is ever added to a system that lacks one.

### Storage

| Schema | Tier | Holds |
|---|---|---|
| `sky_ops` | — | Latency, cost ledger, audit log, host health |
| `sky_memory` | 3 | Operational memory (retrievable) + raw archive (**not** retrievable) |
| `sky_knowledge` | 2 | Allowlisted document collections only |

Schemas are separated physically from the first migration so that per-tier roles, grants, and backup policy stay cheap. Merging later is easy; splitting later is not.

### Voice *(Phase 4)*

`openWakeWord` → `faster-whisper` → Sky → Piper TTS, streamed end to end. The metric is time-to-first-word, not voice beauty. Barge-in is required. Keyboard and voice coexist permanently — voice is additive, never a replacement.

### Avatar *(Phase 5, earned)*

A VRM model loaded and rendered in the client browser. The server sends state (`idle`, `thinking`, `speaking`, viseme stream) and never a frame. This is what makes a 2013 machine capable of driving a real-time 3D assistant at all.

---

## 4. The privilege model

```
TIER 0  IDENTITY & SECRETS   OAuth tokens · API keys · encryption keys
        └─ The LLM NEVER sees these. Tools broker all access.

TIER 1  ACTION SYSTEMS       Email · calendar · messaging · ActivePieces
        └─ READ  is broad and low-friction
        └─ WRITE requires the approval queue. Reading email ≠ sending email.

TIER 2  KNOWLEDGE            Documents and files
        └─ Allowlisted collections only. Never blanket-RAG a digital life.

TIER 3  MEMORY               Summarized operational memory (retrievable)
        └─ kept separate from the immutable raw archive (not retrievable)
```

Full reasoning and attack surface in [`THREAT-MODEL.md`](THREAT-MODEL.md).

---

## 5. Network topology

```
          ┌─ private, default ─┐         ┌─ public, gated ──────────┐
Clients ──┤  Tailscale mesh    ├── SKY ──┤ Cloudflare Tunnel        │
          │  (WireGuard)       │  NODE   │ + Zero Trust Access      │
          └────────────────────┘         └──────────────────────────┘
                         ↑                            ↑
              no inbound ports              outbound-only tunnel
              no port forwarding            identity-gated, logged
```

Every published container port binds to `127.0.0.1`. The router forwards nothing. See DL-004.

---

## 6. What Phase 0 actually is

Foundation only. At the end of Phase 0 Sky is reachable, instrumented, backed up, and **restore-tested** — and cannot think yet. That is the correct order. Reasoning arrives in Phase 1; the ability to *act* arrives in Phase 2, which is the point at which this stops being ChatGPT with extra steps.

---

## 7. Open architectural questions

| # | Question | Decide by |
|---|---|---|
| 1 | Does `sky-core` stay in-process with the gateway or split into its own container? | Phase 2 |
| 2 | Embedding model + dimension — affects the `vector(n)` column | Phase 3 |
| 3 | Local Whisper vs. cloud STT after benchmarking | Phase 4 |
| 4 | Approval queue surface: web UI, push notification, or both | Phase 6 |
| 5 | Does the Overseer role migrate into the server, or stay distinct? (DL-001) | Phase 7 |
