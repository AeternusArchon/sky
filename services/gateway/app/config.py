"""
Configuration. Reads environment only — never a committed file.

TIER 0 RULE: values loaded here that are marked SECRET must never be
returned by an API route, written to a log line, or placed in an LLM
context window. `Settings.public_dict()` is the only safe serialization
and it is an allowlist, not a denylist — new secrets are excluded by
default because they simply are not in the list.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env(key: str, default: str = "") -> str:
    return os.environ.get(key, default).strip()


def _env_int(key: str, default: int) -> int:
    try:
        return int(_env(key) or default)
    except ValueError:
        return default


def _env_float(key: str, default: float) -> float:
    try:
        return float(_env(key) or default)
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    # ─── Identity (DL-001) ────────────────────────────────────────────
    identity_name: str = field(default_factory=lambda: _env("SKY_IDENTITY_NAME", "Sky Prime"))
    address_name: str = field(default_factory=lambda: _env("SKY_ADDRESS_NAME", "Sky"))
    env: str = field(default_factory=lambda: _env("SKY_ENV", "development"))
    version: str = field(default_factory=lambda: _env("SKY_VERSION", "0.1.0-phase0"))

    # ─── Gateway ──────────────────────────────────────────────────────
    log_level: str = field(default_factory=lambda: _env("LOG_LEVEL", "INFO").upper())
    allowed_origins: tuple[str, ...] = field(
        default_factory=lambda: tuple(
            o.strip() for o in _env("GATEWAY_ALLOWED_ORIGINS").split(",") if o.strip()
        )
    )

    # ─── Postgres ─────────────────────────────────────────────────────
    pg_host: str = field(default_factory=lambda: _env("POSTGRES_HOST", "postgres"))
    pg_port: int = field(default_factory=lambda: _env_int("POSTGRES_PORT", 5432))
    pg_user: str = field(default_factory=lambda: _env("POSTGRES_USER", "sky"))
    pg_password: str = field(default_factory=lambda: _env("POSTGRES_PASSWORD"))  # SECRET
    pg_db: str = field(default_factory=lambda: _env("POSTGRES_DB", "sky"))

    # ─── Cost guardrails (Risk #9) ────────────────────────────────────
    monthly_cost_cap_usd: float = field(
        default_factory=lambda: _env_float("SKY_MONTHLY_COST_CAP_USD", 50.0)
    )
    cost_alert_threshold: float = field(
        default_factory=lambda: _env_float("SKY_COST_ALERT_THRESHOLD", 0.75)
    )

    @property
    def dsn(self) -> str:
        return (
            f"postgresql://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_db}"
        )

    def public_dict(self) -> dict:
        """Allowlist. Anything not named here never leaves the process."""
        return {
            "identity": self.identity_name,
            "address": self.address_name,
            "env": self.env,
            "version": self.version,
            "cost_cap_usd": self.monthly_cost_cap_usd,
        }


settings = Settings()
