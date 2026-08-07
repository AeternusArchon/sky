-- ═══════════════════════════════════════════════════════════════════════
--  SKY — base schema
--  Runs ONCE, on first boot of an empty sky-pgdata volume.
--
--  Schemas mirror the privilege tiers in docs/THREAT-MODEL.md. Keeping
--  them physically separate now makes per-tier roles, grants, and backup
--  policies cheap later. Merging them later is not cheap.
-- ═══════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS vector;      -- Tier 2/3 retrieval
CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS sky_ops;        -- telemetry, audit, health
CREATE SCHEMA IF NOT EXISTS sky_memory;     -- TIER 3
CREATE SCHEMA IF NOT EXISTS sky_knowledge;  -- TIER 2

COMMENT ON SCHEMA sky_ops       IS 'Operational telemetry, cost ledger, audit log, host health.';
COMMENT ON SCHEMA sky_memory    IS 'TIER 3. Operational memory (retrievable) + raw archive (NOT retrievable).';
COMMENT ON SCHEMA sky_knowledge IS 'TIER 2. Allowlisted document collections only. Never blanket-RAG.';


-- ─── Shared: updated_at trigger ────────────────────────────────────────
CREATE OR REPLACE FUNCTION sky_ops.touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;
