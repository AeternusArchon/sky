-- ═══════════════════════════════════════════════════════════════════════
--  sky_ops — telemetry, cost, audit, health
--  Risks #6 (latency), #9 (cost drift), #3 (blast radius), #7 (fatigue)
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Latency (Risk #6) ─────────────────────────────────────────────────
-- ttft_ms is the number that decides adoption. total_ms is context.
CREATE TABLE IF NOT EXISTS sky_ops.request_latency (
    id          bigserial PRIMARY KEY,
    trace_id    text        NOT NULL,
    label       text        NOT NULL,
    ttft_ms     numeric(10,2),
    total_ms    numeric(10,2),
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_latency_created ON sky_ops.request_latency (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_latency_label   ON sky_ops.request_latency (label, created_at DESC);

COMMENT ON COLUMN sky_ops.request_latency.ttft_ms
  IS 'Time to first token. If this regularly exceeds ~2000ms for voice, adoption dies.';


-- ─── Cost ledger (Risk #9) ─────────────────────────────────────────────
-- Append-only. Never updated, never deleted. The gateway reads MTD sum
-- against SKY_MONTHLY_COST_CAP_USD and refuses calls past the cap.
CREATE TABLE IF NOT EXISTS sky_ops.llm_cost_ledger (
    id             bigserial PRIMARY KEY,
    trace_id       text        NOT NULL,
    provider       text        NOT NULL,
    model          text        NOT NULL,
    input_tokens   integer     NOT NULL DEFAULT 0,
    output_tokens  integer     NOT NULL DEFAULT 0,
    cost_usd       numeric(12,6) NOT NULL DEFAULT 0,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cost_created ON sky_ops.llm_cost_ledger (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cost_model   ON sky_ops.llm_cost_ledger (model, created_at DESC);

CREATE OR REPLACE VIEW sky_ops.cost_by_day AS
SELECT date_trunc('day', created_at)::date AS day,
       model,
       count(*)                            AS calls,
       sum(input_tokens)                   AS input_tokens,
       sum(output_tokens)                  AS output_tokens,
       round(sum(cost_usd), 4)             AS cost_usd
FROM sky_ops.llm_cost_ledger
GROUP BY 1, 2
ORDER BY 1 DESC, 6 DESC;


-- ─── Audit log (Risk #3 — blast radius) ────────────────────────────────
-- EVERY tool invocation lands here. Enforced in Phase 6; the table exists
-- now so nothing has to be backfilled and no tool ships un-audited.
CREATE TABLE IF NOT EXISTS sky_ops.audit_log (
    id           bigserial PRIMARY KEY,
    trace_id     text        NOT NULL,
    actor        text        NOT NULL DEFAULT 'sky',
    tool         text        NOT NULL,
    tier         smallint    NOT NULL CHECK (tier BETWEEN 0 AND 3),
    operation    text        NOT NULL CHECK (operation IN ('read','write','delete','execute')),
    target       text,
    approved_by  text,                       -- NULL = no human approval required
    approved_at  timestamptz,
    outcome      text        NOT NULL DEFAULT 'pending'
                 CHECK (outcome IN ('pending','allowed','denied','error','completed')),
    detail       jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON sky_ops.audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tool    ON sky_ops.audit_log (tool, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_pending ON sky_ops.audit_log (outcome)
    WHERE outcome = 'pending';

COMMENT ON TABLE sky_ops.audit_log
  IS 'Every tool call. Write/delete on Tier 1 requires approved_by before outcome=completed.';


-- ─── Host health (Risk #7 — 2013 hardware) ─────────────────────────────
CREATE TABLE IF NOT EXISTS sky_ops.host_health (
    id           bigserial PRIMARY KEY,
    cpu_temp_c   numeric(5,1),
    load_1m      numeric(6,2),
    mem_used_pct numeric(5,2),
    disk_used_pct numeric(5,2),
    smart_ok     boolean,
    uptime_s     bigint,
    raw          jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_health_created ON sky_ops.host_health (created_at DESC);


-- ─── Retention ─────────────────────────────────────────────────────────
-- Telemetry is operational, not sacred. Cost ledger and audit log are NOT
-- pruned here — those are evidence.
CREATE OR REPLACE FUNCTION sky_ops.prune_telemetry(keep_days integer DEFAULT 90)
RETURNS TABLE (table_name text, rows_deleted bigint)
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
  DELETE FROM sky_ops.request_latency WHERE created_at < now() - (keep_days || ' days')::interval;
  GET DIAGNOSTICS n = ROW_COUNT;
  table_name := 'request_latency'; rows_deleted := n; RETURN NEXT;

  DELETE FROM sky_ops.host_health WHERE created_at < now() - (keep_days || ' days')::interval;
  GET DIAGNOSTICS n = ROW_COUNT;
  table_name := 'host_health'; rows_deleted := n; RETURN NEXT;
END $$;
