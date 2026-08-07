"""
sky-gateway — Phase 0 stub.

What this is:  proof the box is online, reachable, wired to Postgres, and
               instrumented.
What this is NOT: an assistant. There is no reasoning here yet. Phase 1
               adds the LiteLLM router, the persona layer, and real streaming.

The cancel/stop path is stubbed at the protocol level from day one on
purpose — retrofitting interruption into a streaming system that never had
it is painful, and an assistant you cannot interrupt is an assistant you
stop using.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import time
from datetime import datetime, timezone

import asyncpg
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse

from .config import settings
from .telemetry import Timer, month_to_date_cost, record_latency

logging.basicConfig(
    level=settings.log_level,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("sky.gateway")

BOOT_TS = time.time()
pool: asyncpg.Pool | None = None

app = FastAPI(
    title="sky-gateway",
    version=settings.version,
    docs_url=None,       # no public API docs surface
    redoc_url=None,
    openapi_url=None,
)


# ═══════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═══════════════════════════════════════════════════════════════════════

@app.on_event("startup")
async def startup() -> None:
    global pool
    for attempt in range(1, 11):
        try:
            pool = await asyncpg.create_pool(settings.dsn, min_size=1, max_size=5)
            log.info("postgres connected")
            break
        except Exception as exc:                                  # noqa: BLE001
            log.warning("postgres not ready (%s/10): %s", attempt, exc)
            await asyncio.sleep(3)
    else:
        # Graceful degradation, not a crash loop. The page still serves;
        # /health reports the truth. Risk #7 — maintenance fatigue.
        log.error("postgres unavailable — running degraded")


@app.on_event("shutdown")
async def shutdown() -> None:
    if pool is not None:
        await pool.close()


# ═══════════════════════════════════════════════════════════════════════
#  Health
# ═══════════════════════════════════════════════════════════════════════

async def _db_status() -> dict:
    if pool is None:
        return {"connected": False, "pgvector": False, "error": "no pool"}
    try:
        async with pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
            has_vec = await conn.fetchval(
                "SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector')"
            )
            ver = await conn.fetchval("SHOW server_version")
        return {"connected": True, "pgvector": bool(has_vec), "server_version": ver}
    except Exception as exc:                                      # noqa: BLE001
        return {"connected": False, "pgvector": False, "error": str(exc)[:200]}


@app.get("/health")
async def health() -> JSONResponse:
    db = await _db_status()
    mtd = await month_to_date_cost(pool)
    cap = settings.monthly_cost_cap_usd
    body = {
        "status": "ok" if db["connected"] else "degraded",
        "phase": 0,
        **settings.public_dict(),
        "uptime_seconds": round(time.time() - BOOT_TS, 1),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "database": db,
        "cost": {
            "month_to_date_usd": round(mtd, 4),
            "cap_usd": cap,
            "pct_of_cap": round(mtd / cap, 4) if cap else None,
            "alerting": bool(cap and mtd / cap >= settings.cost_alert_threshold),
        },
    }
    return JSONResponse(body, status_code=200 if db["connected"] else 503)


# ═══════════════════════════════════════════════════════════════════════
#  The Phase 0 deliverable
# ═══════════════════════════════════════════════════════════════════════

_PAGE = """<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sky</title><style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0b0e14;
 color:#dfe5f0;font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
 background-image:radial-gradient(700px 340px at 50% 0%,rgba(90,169,255,.14),transparent 65%)}
.c{text-align:center;padding:32px;max-width:440px}
.p{display:inline-flex;align-items:center;gap:10px;border:1px solid rgba(74,222,128,.35);
 background:rgba(74,222,128,.09);color:#4ade80;border-radius:999px;padding:8px 18px;
 font:600 11px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.18em;
 text-transform:uppercase;margin-bottom:26px}
.d{width:8px;height:8px;border-radius:50%;background:#4ade80;box-shadow:0 0 12px #4ade80;
 animation:b 2.4s ease-in-out infinite}
@keyframes b{0%,100%{opacity:1}50%{opacity:.35}}
h1{font-size:clamp(34px,9vw,58px);margin:0 0 10px;letter-spacing:-.03em;font-weight:700}
p{margin:0 0 30px;color:#98a3b8}
dl{display:grid;grid-template-columns:auto auto;gap:8px 20px;justify-content:center;
 font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;margin:0}
dt{color:#6b7689;text-align:right}dd{margin:0;color:#dfe5f0;text-align:left}
.err{color:#ff8f4d}
</style></head><body><div class="c">
<div class="p"><span class="d"></span> System Online</div>
<h1>Sky is online.</h1>
<p>Phase 0 — Foundation. She can be reached. She cannot yet think.</p>
<dl id="s"><dt>loading</dt><dd>…</dd></dl>
</div><script>
fetch('/health').then(r=>r.json()).then(h=>{
 const db=h.database||{};
 const rows=[['identity',h.identity],['version',h.version],['phase','0 — foundation'],
  ['database',db.connected?'connected':'<span class="err">unreachable</span>'],
  ['pgvector',db.pgvector?'loaded':'<span class="err">missing</span>'],
  ['uptime',h.uptime_seconds+'s']];
 document.getElementById('s').innerHTML=
  rows.map(([k,v])=>`<dt>${k}</dt><dd>${v}</dd>`).join('');
}).catch(()=>{document.getElementById('s').innerHTML=
 '<dt>gateway</dt><dd class="err">health check failed</dd>';});
</script></body></html>"""


@app.get("/", response_class=HTMLResponse)
async def index() -> HTMLResponse:
    return HTMLResponse(_PAGE)


# ═══════════════════════════════════════════════════════════════════════
#  WebSocket — protocol skeleton, echo only
#
#  Client → {"type":"message","text":"..."}  |  {"type":"cancel"}
#  Server → {"type":"token"|"done"|"cancelled"|"error", ...}
#
#  Phase 1 replaces _respond() with the LLM stream. The cancel semantics,
#  the frame shapes, and the telemetry hooks stay exactly as they are.
# ═══════════════════════════════════════════════════════════════════════

@app.websocket("/ws")
async def ws(sock: WebSocket) -> None:
    origin = sock.headers.get("origin")
    if settings.allowed_origins and origin and origin not in settings.allowed_origins:
        await sock.close(code=4403)
        log.warning("ws rejected origin=%s", origin)
        return

    await sock.accept()
    task: asyncio.Task | None = None
    log.info("ws open")

    async def _respond(text: str, timer: Timer) -> None:
        """Phase 0 placeholder: echoes word by word so streaming + cancel are real."""
        try:
            for i, word in enumerate((f"[echo] {text}").split()):
                if i == 0:
                    timer.mark_first_token()
                await sock.send_json({"type": "token", "text": word + " "})
                await asyncio.sleep(0.04)
            await sock.send_json({"type": "done", "trace_id": timer.trace_id})
        except asyncio.CancelledError:
            with contextlib.suppress(Exception):
                await sock.send_json({"type": "cancelled", "trace_id": timer.trace_id})
            raise

    try:
        while True:
            raw = await sock.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await sock.send_json({"type": "error", "error": "invalid json"})
                continue

            kind = msg.get("type")

            if kind == "cancel":
                if task and not task.done():
                    task.cancel()
                continue

            if kind != "message":
                await sock.send_json({"type": "error", "error": f"unknown type: {kind}"})
                continue

            if task and not task.done():
                task.cancel()          # a new turn always preempts the old one

            timer = Timer("ws.turn")
            timer.__enter__()

            async def _run(t: Timer = timer, text: str = str(msg.get("text", ""))) -> None:
                try:
                    await _respond(text, t)
                finally:
                    t.__exit__(None, None, None)
                    await record_latency(
                        pool, label=t.label, trace_id=t.trace_id,
                        ttft_ms=t.ttft_ms, total_ms=t.total_ms,
                    )

            task = asyncio.create_task(_run())

    except WebSocketDisconnect:
        log.info("ws closed")
    finally:
        if task and not task.done():
            task.cancel()
