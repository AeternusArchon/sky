# SKY

**A self-hosted agentic AI assistant platform running on a 2013 Mac Pro.**

Sky reasons over personal context and executes real actions across real systems — calendar, email, and automation platforms — behind a scoped permission model. Cloud LLMs do the reasoning. The browser does the rendering. The Mac Pro orchestrates, and only orchestrates.

> **Status:** Phase 0 — Foundation. Not yet functional as an assistant.
> **Plan version:** v1.2

---

## Why this exists (and why it looks like this)

The hardware is the interesting constraint. A 2013 Mac Pro has dual AMD FirePro D-series GPUs, which have effectively no modern ML ecosystem support — no CUDA, no usable ROCm path, no practical local inference at useful speed. The CPU predates AVX2, which also handicaps CPU-based inference.

So rather than fight the hardware, the architecture splits work by where it actually belongs:

| Concern | Where it runs | Why |
|---|---|---|
| **Reasoning** | Cloud LLM APIs | The box cannot do this. Full stop. |
| **Rendering** (3D avatar) | Client browser, WebGL | The server draws zero frames |
| **Retrieval** | Local Postgres + pgvector | Cheap, private, fast enough |
| **Orchestration** | Local FastAPI + Docker | This is what the box is good at |
| **Secrets** | Local, isolated, never in LLM context | Security boundary, not convenience |

That split *is* the engineering story. Every design decision in `docs/DECISIONS.md` records why.

---

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full picture and [`docs/diagrams/system.txt`](docs/diagrams/system.txt) for the canonical diagram.

```
CLIENTS (PC · iPhone · iPad)  ──WSS──>  SKY NODE (Mac Pro · Debian 13 · Docker)
   VRM avatar · mic · speaker              gateway → core → {memory, knowledge, actions}
   WebGL renders HERE                      Tier 0 secrets never enter LLM context
```

### The privilege model

Sky does not get host access. Sky gets tools. Tools get permissions. Permissions get scoped.

| Tier | Contents | Rule |
|---|---|---|
| **0** | OAuth refresh tokens, API keys, encryption keys | The LLM **never** sees these. Tools broker all access. |
| **1** | Email, calendar, messaging, automation | Read is broad. **Write requires the approval queue.** |
| **2** | Documents and files | Allowlisted collections only. No blanket-RAG. |
| **3** | Memory | Operational memory (retrievable) separate from raw archive (not retrievable). |

Full reasoning in [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md).

---

## Repo layout

```
sky/
├── docker-compose.yml       # the whole stack
├── .env.example             # copy to .env — never committed
├── Makefile                 # common operations
├── docs/
│   ├── ARCHITECTURE.md      # what it is and why
│   ├── THREAT-MODEL.md      # what could go wrong
│   ├── DECISIONS.md         # decision log — the portfolio artifact
│   └── diagrams/
├── services/
│   └── gateway/             # FastAPI · sessions · streaming · telemetry
├── db/init/                 # schema, runs once on first DB start
└── ops/
    ├── backup/              # backup.sh + restore.sh (restore is TESTED)
    ├── health/              # 2013 hardware needs watching
    └── tunnel/              # Cloudflare Tunnel + Access notes
```

---

## Quickstart (SKY Node)

```bash
git clone <this-repo> /srv/sky
cd /srv/sky

cp .env.example .env
chmod 600 .env                    # Tier 0 lives here for now — treat it accordingly
$EDITOR .env                      # fill in the blanks

docker compose up -d              # postgres + gateway
curl -s localhost:8080/health | jq
```

Then open `http://<node>:8080` — you should see **"Sky is online."**

For the tunnel:

```bash
docker compose --profile tunnel up -d
```

See `ops/tunnel/README.md` first — the tunnel needs a token before it does anything useful.

---

## Make targets

| Command | Does |
|---|---|
| `make up` | Start the stack |
| `make down` | Stop it |
| `make logs` | Follow all logs |
| `make health` | Gateway health + host health as JSON |
| `make psql` | Shell into Postgres |
| `make backup` | Run a backup |
| `make restore-test` | **Restore drill into a throwaway DB.** Run monthly. |

---

## Build log

This is being built in public during an active job search, on a strict **70/30 rule** — 70% job search, 30% this. Sky loses every scheduling conflict.

Every phase produces one usable capability, then stops. The finish line is defined and the backlog is where new ideas go.

**Published:** engineering, architecture, threat model, decisions, metrics.
**Never published:** personal data. All demos use synthetic data.

---

## License

MIT — see [`LICENSE`](LICENSE).
