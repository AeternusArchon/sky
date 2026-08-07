# Decision Log

Every non-obvious decision, written at the time it was made — not reconstructed afterward.

**Why this file exists:** the interview story is not *"I built an AI server."* It is *"here is why the design is what it is, and here is what broke along the way."* That costs minutes per phase to record and is nearly impossible to fabricate later. This is the highest-leverage document in the repo.

**Format:** one entry per decision. Never edit a past entry — supersede it with a new one and mark the old one accordingly.

---

## DL-001 — Identity is Sky Prime, embodied

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** Pre-build

**Decision.** The assistant running on SKY Node is *Sky Prime*, the same identity that already exists, now self-hosted and hardware-independent. It is not a new assistant and not a sibling. The conversational address — and the eventual wake word — is the short form, **"Sky."**

**Context.** Two positions were argued. One held that a self-hosted build should feel like a distinct assistant with its own relationship. The other held that identity should be separate from hardware and portable, so this build is the existing identity gaining a body rather than a third entity being created.

**Rationale.** Continuity of identity over continuity of hardware. The body is replaceable — today a 2013 Mac Pro, later anything. The identity is not. A "third Sky" would fragment context across entities that each know part of the picture.

**Consequences.**

| | |
|---|---|
| Persona layer | Declares continuity, not creation. No cold-start introduction. |
| Memory | Genesis seed required at Phase 1: relationship, projects, preferences, prior decisions. |
| Provenance | Seeded memories carry `source='seed'` and are correctable independently of lived context (Risk #15). Enforced by a CHECK constraint in `db/init/003_memory.sql`. |
| Wake word | "Sky," not "Sky Prime." Two syllables detect better than three, and the plosive hurts. Decided now while it is free; implemented Phase 9. |

**Cost of being wrong:** low. The persona is a config file plus a memory seed.

---

## DL-002 — Reasoning runs in the cloud; the Mac Pro orchestrates

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** 0

**Decision.** No local LLM inference. Reasoning goes to hosted APIs behind a router. The Mac Pro runs orchestration, retrieval, and storage only. The browser renders the avatar.

**Context.** The host is a Mac Pro 6,1 (2013): dual AMD FirePro D-series GPUs and a pre-AVX2 Xeon.

**Rationale.** The FirePro cards have no practical modern ML path — no CUDA, no usable ROCm for this generation. The CPU lacks AVX2, handicapping CPU inference as well. Local inference here is not a tradeoff, it is a dead end (Risk #14). Splitting the workload by where it belongs turns the hardware limitation into the architecture.

**Consequences.** Ongoing API cost — which is why the cost ledger and hard cap shipped in Phase 0 rather than after the first surprising bill (Risk #9). Network dependency for reasoning; retrieval and memory stay local and private.

**Revisit when:** the host changes, or a small local model becomes worthwhile as an intent gate.

---

## DL-003 — Local is not a security boundary

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** 0

**Decision.** Adopt a four-tier privilege model. The LLM never receives credentials, never gets host access, and never has write authority on external systems without human approval. Tools broker everything.

**Context.** The initial design implicitly granted broad access on the reasoning that the system runs on hardware the owner physically controls.

**Rationale.** That reasoning is wrong. One box will hold email, calendar, documents, credentials, and conversation history — a single blast radius (Risk #3). Physical control of the hardware does not constrain what a model does with the access it is handed. Prompt injection through an email body is a realistic path from "summarize my inbox" to "act on attacker instructions."

**Consequences.** Read and write are never equivalent. Documents are allowlisted, never blanket-indexed. Schemas are physically separated by tier from the first migration, because retrofitting boundaries onto a system that already has broad access is expensive and usually does not fully happen.

**Implemented so far:** `Settings.public_dict()` in `services/gateway/app/config.py` is an allowlist rather than a denylist — a secret added next month is excluded because it simply is not named, not because anyone remembered. Verified: `/health` returns zero credential fields.

**Enforced:** Phase 6. **Designed:** now.

---

## DL-004 — No inbound ports; reachability is private-first

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** 0

**Decision.** Nothing binds to a routable interface. All container ports publish to `127.0.0.1` only. The router forwards nothing.

**Rationale.** A forwarded port is a permanent, unauthenticated attack surface aimed at a box that holds everything in DL-003. Verified 2026-08-07: `casa.home.overlordlabs.net` resolves to `10.0.0.69`, an RFC1918 private address. Nothing on SKY Node is reachable from the public internet.

**Note.** This posture predates the decision — every pre-existing container on the host was already loopback-bound by the operator. This entry formalizes an existing practice rather than introducing one.

---

## DL-005 — Docker group membership accepted as root-equivalent

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** 0

**Decision.** The operator's user account stays in the `docker` group. Rootless Docker was considered and rejected for this deployment.

**Context.** Membership in the `docker` group is **not** a lesser privilege than `sudo`. Anyone in that group can mount the host filesystem into a privileged container and read or modify anything — the same power, without a password prompt.

**Rationale.** Accepted deliberately, not overlooked:

- Single-admin machine, no other user accounts
- No inbound ports; no network-reachable path to an unprivileged shell (DL-004)
- Rootless Docker complicates container networking and cgroup delegation enough to cost a working session
- The threat model's actual adversaries — opportunistic scanners, credential theft, prompt injection — are not mitigated by rootless mode

**Revisit when:** a second user account is added, the host gains an inbound path, or SKY Node moves to shared hardware.

---

## DL-006 — Percent-encode credentials before they enter a connection URL

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** 0
**Category:** Bug postmortem

**Symptom.** After the first deployment, `sky-gateway` reported `unhealthy` while running normally. Ports mapped, process alive, Postgres healthy. `docker logs sky-gateway` showed:

```
WARNING sky.gateway postgres not ready (1/10): invalid literal for int() with base 10: 'W3ajW'
```

Repeated ten times, three seconds apart, then: `ERROR postgres unavailable — running degraded`.

**Root cause.** `config.py` built the Postgres DSN by string interpolation:

```python
f"postgresql://{user}:{password}@{host}:{port}/{db}"
```

The password was generated with `openssl rand -base64 32`. **Base64 output can contain `/`.** In a URL, `/` terminates the authority section. So:

```
postgresql://sky:W3ajW/rest-of-password@postgres:5432/sky
                      ▲ parser stops here
```

The parser read `host = "sky"`, `port = "W3ajW"`, discarded the remainder, and `int("W3ajW")` raised `ValueError`.

**Why it presented as a health failure rather than a crash.** By design. `/health` returns HTTP 503 when the database is unreachable, and the container health check requires 200. The gateway stayed up and reported degraded rather than crash-looping — graceful degradation working as intended (Risk #7), which is also why the diagnosis was available in the logs instead of a restart loop.

**Fix.**

```python
from urllib.parse import quote

user = quote(self.pg_user, safe="")
password = quote(self.pg_password, safe="")
return f"postgresql://{user}:{password}@{self.pg_host}:{self.pg_port}/{self.pg_db}"
```

`safe=""` is load-bearing. `quote()` leaves `/` unescaped by default — the exact character that caused the failure.

**Rejected alternative:** regenerating the password as hex to avoid special characters. That hides the bug rather than fixing it, and the next credential — an API key, an OAuth secret — would reintroduce it.

**Generalization.** Never concatenate a value into a URL. Encode it. The same class of bug affects query strings containing `&`, `?`, `#`, `+`, or spaces.

---

## DL-007 — Configuration is baked into images, never bind-mounted

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** 0
**Category:** Bug postmortem

**Symptom.** After the gateway recovered, `/health` reported:

```json
"database": { "connected": true, "pgvector": false }
```

The database was reachable but had no extension, no schemas, and no tables — while reporting `status: ok`.

**Root cause.** `docker-compose.yml` supplied the schema via a bind mount:

```yaml
volumes:
  - ./db/init:/docker-entrypoint-initdb.d:ro
```

Portainer clones a Repository stack to `/data/compose/N` — a path **inside the Portainer container**. Docker resolves bind mounts against the **host** filesystem, where that path does not exist.

**Docker's behaviour when a bind-mount source is missing is to create an empty directory, not to fail.** Postgres started, found no scripts, and initialized a valid but entirely empty database. Confirmed by `docker exec sky-postgres ls -la /docker-entrypoint-initdb.d/` returning only `.` and `..`.

**Fix.** `db/Dockerfile`:

```dockerfile
FROM pgvector/pgvector:pg17
COPY init/ /docker-entrypoint-initdb.d/
RUN chmod 0444 /docker-entrypoint-initdb.d/*.sql
```

Compose now builds Postgres locally with `pull_policy: build`. The image carries its own schema; the host is no longer part of the equation.

**Required cleanup.** Postgres runs init scripts only against an empty data directory. The existing `sky-pgdata` volume had to be deleted (`docker rm -f` the containers, then `docker volume rm sky-pgdata`) before init would run. No data was lost — there was none.

**Rejected alternative:** running the SQL manually via `psql`. It would have worked immediately and evaporated the next time the volume was recreated. That violates the plan's backup layer 3 — *infrastructure reproducible from Git*.

**Generalization.** Under any orchestrator that clones or relocates the compose context, relative bind-mount paths are unreliable. Anything a container **needs to exist** belongs in the image. Bind mounts are for data that must outlive the image, not for configuration that defines it.

**Verified after fix:**

```
 table_schema | tables        "pgvector": true
--------------+--------
 sky_memory   |      3
 sky_ops      |      5
```

---

## DL-008 — Deploy via Portainer Repository stack (GitOps)

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** 0

**Decision.** SKY deploys as a Portainer *Repository* stack pointed at this public GitHub repo. Secrets are supplied through Portainer's stack environment variables. No `.env` file is placed on the host, and no files are copied to the server by hand.

**Context.** The operator's five existing services were all created through Portainer's web UI, not by managing files over SSH. An initial filesystem-shaped delivery (`/srv/sky` + `docker compose up`) did not match how this machine is actually operated.

**Rationale.** The repo becomes the single source of truth; the server holds only a copy. Configuration cannot silently drift from what is documented, because the documented thing *is* what runs. Updates are "edit on GitHub → Pull and redeploy."

**Consequences.**

- `.env` is gitignored and therefore absent from the clone, so `env_file:` cannot be used. Services read `${VAR}` substitutions from Portainer's environment box instead. **The measure that keeps secrets out of GitHub is the same one that requires them to arrive another way** — a consequence to design around, not a flaw.
- `pull_policy: build` is mandatory on built services. Without it, redeploy silently reuses the previous image and code changes appear to have no effect.
- Bind-mounted configuration is unusable (see DL-007).

---

## DL-009 — Caddy serves Sky; the Cloudflare Tunnel is not deployed

**Date:** 2026-08-07 · **Status:** ✅ Final · **Phase:** 0

**Decision.** `sky.home.overlordlabs.net` is served by the host's existing Caddy instance, reverse-proxying to `127.0.0.1:18090`. The `cloudflared` service remains defined in `docker-compose.yml` behind a `profiles: [tunnel]` guard and is **not running**.

**Context.** The host already ran Caddy with a wildcard certificate for `*.home.overlordlabs.net`, obtained via the **DNS-01 challenge** against Cloudflare. That is why valid TLS exists with zero inbound ports open (DL-004) — domain ownership is proven by writing a DNS record rather than serving a file over port 80.

**Rationale.** Route around what already works. Adding a second ingress path would duplicate a solved problem and create two places for hostname configuration to drift.

**Side effect worth recording.** Because the certificate is a **wildcard**, Certificate Transparency logs publish `*.home.overlordlabs.net` and not the individual service hostnames. Per-service names are therefore *not* publicly enumerable via CT — a property that per-subdomain certificates would not have.

**Port note.** Sky's gateway publishes on host port **18090**, not 8080. Port 8080 is held by `casaos-gateway`. 18090 follows the operator's existing `1xxxx` convention (ActivePieces 18081, n8n 15678).

**🔴 Open obligation — blocks Phase 2.** Caddy currently provides TLS but **no authentication** for Sky. Every other service behind this proxy enforces its own login; Sky has none, because none was built. Present exposure is limited to the local network (`10.0.0.69`, RFC1918), which is acceptable while Sky holds no data.

**This must be closed before any email or calendar credential is issued to Sky.** An assistant with inbox access must not be one known hostname away from anyone on the network. Obscurity buys time; it does not buy security.

---

<!-- ────────────────────────────────────────────────────────────────────
     TEMPLATE — copy for each new decision

## DL-0NN — <one-line decision in the imperative>

**Date:** YYYY-MM-DD · **Status:** ✅ Final | 🟡 Provisional | ⛔ Superseded by DL-0NN · **Phase:** N

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
| _pending_ | local | — | — | — | **Phase 0 does not complete until this row says PASS** |
