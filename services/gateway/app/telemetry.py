"""
Telemetry scaffolding — built in Phase 0, before there is anything to measure.

Two numbers decide whether this project survives:

  1. TIME TO FIRST TOKEN (Risk #6) — if Sky is slower than opening ChatGPT,
     Sky loses, no matter how good the answer is.
  2. COST PER DAY (Risk #9) — agent loops and fat contexts turn a $12/mo
     hobby into a $180 surprise.

Instrumenting after the fact means guessing. Instrumenting now costs an
afternoon and is honest for the life of the project.
"""

from __future__ import annotations

import contextlib
import logging
import time
import uuid
from typing import Any

log = logging.getLogger("sky.telemetry")


class Timer:
    """
    Measures wall-clock in milliseconds, with an explicit first-token mark.

        with Timer("chat.turn") as t:
            ...
            t.mark_first_token()      # <- the number that actually matters
            ...
        t.ttft_ms, t.total_ms
    """

    __slots__ = ("label", "_start", "_first_token", "_end", "trace_id")

    def __init__(self, label: str, trace_id: str | None = None) -> None:
        self.label = label
        self.trace_id = trace_id or uuid.uuid4().hex[:12]
        self._start: float | None = None
        self._first_token: float | None = None
        self._end: float | None = None

    def __enter__(self) -> "Timer":
        self._start = time.perf_counter()
        return self

    def __exit__(self, *exc: Any) -> None:
        self._end = time.perf_counter()
        log.info(
            "telemetry label=%s trace=%s ttft_ms=%s total_ms=%s",
            self.label, self.trace_id, self.ttft_ms, self.total_ms,
        )

    def mark_first_token(self) -> None:
        if self._first_token is None:
            self._first_token = time.perf_counter()

    @staticmethod
    def _ms(a: float | None, b: float | None) -> float | None:
        if a is None or b is None:
            return None
        return round((b - a) * 1000, 2)

    @property
    def ttft_ms(self) -> float | None:
        return self._ms(self._start, self._first_token)

    @property
    def total_ms(self) -> float | None:
        return self._ms(self._start, self._end)


async def record_latency(
    pool, *, label: str, trace_id: str, ttft_ms: float | None, total_ms: float | None
) -> None:
    """Persist one latency sample. Never raises into the request path."""
    if pool is None:
        return
    with contextlib.suppress(Exception):
        async with pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO sky_ops.request_latency
                    (trace_id, label, ttft_ms, total_ms)
                VALUES ($1, $2, $3, $4)
                """,
                trace_id, label, ttft_ms, total_ms,
            )


async def record_cost(
    pool,
    *,
    trace_id: str,
    provider: str,
    model: str,
    input_tokens: int,
    output_tokens: int,
    cost_usd: float,
) -> None:
    """
    Append to the cost ledger.

    Phase 1 wires this to the real LiteLLM response. Phase 0 just guarantees
    the table and the call signature exist, so nothing has to be retrofitted.
    """
    if pool is None:
        return
    with contextlib.suppress(Exception):
        async with pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO sky_ops.llm_cost_ledger
                    (trace_id, provider, model, input_tokens, output_tokens, cost_usd)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                trace_id, provider, model, input_tokens, output_tokens, cost_usd,
            )


async def month_to_date_cost(pool) -> float:
    """Total spend this calendar month. Drives the hard cap and the 75% alert."""
    if pool is None:
        return 0.0
    try:
        async with pool.acquire() as conn:
            val = await conn.fetchval(
                """
                SELECT COALESCE(SUM(cost_usd), 0)::float
                FROM sky_ops.llm_cost_ledger
                WHERE created_at >= date_trunc('month', now())
                """
            )
            return float(val or 0.0)
    except Exception:
        return 0.0
