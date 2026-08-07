-- ═══════════════════════════════════════════════════════════════════════
--  sky_memory — TIER 3
--
--  Two stores, deliberately separate:
--    · memory        — summarized, retrievable, small, correctable
--    · conversation  — raw, immutable, NOT in the retrieval path
--
--  Phase 3 fills these. Phase 1 writes the genesis seed (DL-001) into
--  `memory` with source='seed' so imported Sky Prime context stays
--  distinguishable from lived context. Risk #15.
--
--  The design constraint is not "remember 100,000 things." It is
--  "remember the right 30 without being annoying or creepy."
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS sky_memory.memory (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind        text NOT NULL CHECK (kind IN
                  ('identity','preference','project','person','device','goal','decision')),
    subject     text NOT NULL,
    content     text NOT NULL,

    -- The five fields every memory must carry. Non-negotiable (Risk #11).
    source      text NOT NULL CHECK (source IN ('seed','stated','inferred','tool','correction')),
    confidence  numeric(3,2) NOT NULL DEFAULT 0.80 CHECK (confidence BETWEEN 0 AND 1),
    expires_at  timestamptz,                    -- NULL = no expiry, use sparingly
    deleted_at  timestamptz,                    -- soft delete, always reversible
    superseded_by uuid REFERENCES sky_memory.memory(id),

    embedding   vector(1536),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_memory_touch BEFORE UPDATE ON sky_memory.memory
  FOR EACH ROW EXECUTE FUNCTION sky_ops.touch_updated_at();

-- Only live memories are ever retrieved.
CREATE OR REPLACE VIEW sky_memory.active AS
SELECT * FROM sky_memory.memory
WHERE deleted_at IS NULL
  AND superseded_by IS NULL
  AND (expires_at IS NULL OR expires_at > now());

CREATE INDEX IF NOT EXISTS idx_memory_kind ON sky_memory.memory (kind)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_memory_source ON sky_memory.memory (source);
-- Vector index deferred to Phase 3 — ivfflat wants real data to train on.
-- CREATE INDEX idx_memory_vec ON sky_memory.memory
--   USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

COMMENT ON COLUMN sky_memory.memory.source
  IS 'seed = imported Sky Prime continuity (DL-001). Never treat as lived fact.';


-- ─── Raw archive — immutable, NOT retrievable ──────────────────────────
CREATE TABLE IF NOT EXISTS sky_memory.conversation (
    id          bigserial PRIMARY KEY,
    session_id  uuid NOT NULL,
    role        text NOT NULL CHECK (role IN ('user','assistant','system','tool')),
    content     text NOT NULL,
    trace_id    text,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_conv_session ON sky_memory.conversation (session_id, id);

COMMENT ON TABLE sky_memory.conversation
  IS 'Immutable transcript. Deliberately has NO embedding column — it is not in the retrieval path.';
