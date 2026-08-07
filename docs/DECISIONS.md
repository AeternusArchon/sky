# Decision Log

Every non-obvious decision, written at the time it was made — not reconstructed afterward.

**Why this file exists:** the interview story is not *"I built an AI server."* It is *"here is why the design is what it is."* That answer costs minutes per phase to record and is nearly impossible to fabricate later. This is the highest-leverage document in the repo.

**Format:** one entry per decision. Never edit a past entry — supersede it with a new one and mark the old one accordingly.

---

## DL-001 — Identity is Sky Prime, embodied

**Date:** 2026-08-07
**Status:** ✅ Final
**Phase:** Pre-build

**Decision.** The assistant running on SKY Node is *Sky Prime*, the same identity that already exists, now self-hosted and hardware-independent. It is not a new assistant and not a sibling. The conversational address — and the eventual wake word — is the short form, **"Sky."**

**Context.** Two positions were argued. One held that a self-hosted build should feel like a distinct assistant with its own relationship. The other held that identity should be separate from hardware and portable, so this build is the existing identity gaining a body rather than a third entity being created.

**Rationale.** Continuity of identity over continuity of hardware. The body is replaceable — today a 2013 Mac Pro, later anything. The identity is not. A "third Sky" would fragment context across entities that each know part of the picture.

**Consequences.**

| | |
|---|---|
| Persona layer | Declares continuity, not creation. No cold-start introduction. |
| Memory | Genesis seed required at Phase 1: relationship, projects, preferences, prior decisions. |
| Provenance | Seeded memories carry `source='seed'` and are correctable independently of lived context. New risk registered (#15 — seeded identity drift). |
| Naming | Service namespace (`sky-*`), platform (`SKY Core`), and hardware (`SKY Node`) are unaffected. |
| Wake word | "Sky," not "Sky Prime." Two syllables detect better than three, and the plosive hurts. Decided now while it is free; implemented Phase 9. |

**Cost of being wrong:** low. The persona is a config file plus a memory seed. Reversing this is an afternoon, not a rebuild.

**Open, not blocking:** Sky Prime currently serves as the strategic/challenge voice in the AI Council. Embodying that identity as the always-on daily assistant may pull the role toward operations. Revisit before Phase 7.

---

## DL-002 — Reasoning runs in the cloud; the Mac Pro orchestrates

**Date:** 2026-08-07
**Status:** ✅ Final
**Phase:** 0

**Decision.** No local LLM inference. Reasoning goes to hosted APIs behind a router. The Mac Pro runs orchestration, retrieval, and storage only. The browser renders the avatar.

**Context.** The host is a Mac Pro 6,1 (2013): dual AMD FirePro D-series GPUs and a pre-AVX2 Xeon.

**Rationale.** The FirePro cards have no practical modern ML path — no CUDA, and no usable ROCm support for this generation. The CPU lacks AVX2, which handicaps CPU inference as well. Attempting local inference here is not a tradeoff, it is a dead end (Risk #14). Splitting the workload by where it actually belongs turns the hardware limitation into the architecture.

**Consequences.** Ongoing API cost, which is why the cost ledger and hard cap ship in Phase 0 rather than after the first surprising bill (Risk #9). Network dependency for reasoning; retrieval and memory stay local and private.

**Revisit when:** the host changes, or a small local model becomes worthwhile as an intent gate. Explicitly cut from MVP as premature optimization.

---

## DL-003 — Local is not a security boundary

**Date:** 2026-08-07
**Status:** ✅ Final
**Phase:** 0

**Decision.** Adopt a four-tier privilege model. The LLM never receives credentials, never gets host access, and never has write authority on external systems without human approval. Tools broker everything.

**Context.** The initial design implicitly granted broad access on the reasoning that the system runs on hardware the owner physically controls.

**Rationale.** That reasoning is wrong. One box will hold email, calendar, documents, credentials, and conversation history — a single blast radius (Risk #3). Physical control of the hardware does not constrain what a model does with the access it is handed. Prompt injection through an email body is a realistic path from "summarize my inbox" to "act on attacker instructions."

**Consequences.** Read and write are never equivalent operations. Documents are allowlisted, never blanket-indexed. Schemas are physically separated by tier from the first migration, because retrofitting boundaries onto a system that already has broad access is expensive and usually does not fully happen.

**Enforced:** Phase 6. **Designed:** now.

---

## DL-004 — No inbound ports; reachability is Tailscale-first

**Date:** 2026-08-07
**Status:** ✅ Final
**Phase:** 0

**Decision.** Nothing binds to a routable interface. All container ports publish to `127.0.0.1` only. Private access is Tailscale. Public access is a Cloudflare Tunnel with Zero Trust Access in front of it. The router forwards nothing.

**Rationale.** A forwarded port is a permanent, unauthenticated attack surface aimed at a box that holds everything in DL-003. An outbound-only tunnel with identity-gated access has no listening surface to scan, and Access failures are logged and revocable.

**Consequences.** Cloudflare becomes a dependency for off-network reach. Tailscale is the fallback path and remains the default. NordVPN must stay off this host or be hard split-tunneled (Risk #12).

---

<!-- ────────────────────────────────────────────────────────────────────
     TEMPLATE — copy for each new decision

## DL-0NN — <one-line decision in the imperative>

**Date:** YYYY-MM-DD
**Status:** ✅ Final | 🟡 Provisional | ⛔ Superseded by DL-0NN
**Phase:** N

**Decision.** What was decided.
**Context.** What was true that forced the choice.
**Rationale.** Why this over the alternative. Name the alternative.
**Consequences.** What this costs, and what it now makes hard.
**Revisit when:** the condition that would reopen this.
──────────────────────────────────────────────────────────────────── -->

---

## Restore drill log

Risk #4. A backup that has never been restored is a theory. Every drill gets a line here — including the failures, which are the useful ones.

| Date | Source | Result | Schemas | Tables | Notes |
|---|---|---|---|---|---|
| _pending_ | local | — | — | — | Phase 0 does not complete until this row says PASS |
