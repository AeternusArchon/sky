"""
config.py — how Sky learns her settings.

WHAT THIS FILE DOES
Every setting Sky needs (database address, password, model names, cost caps)
arrives as an ENVIRONMENT VARIABLE — a key/value pair the operating system
hands to the program when it starts. Portainer sets those. This file reads
them, converts them to the right types, and hands the rest of the app one
tidy object called `settings`.

WHY NOT JUST READ A CONFIG FILE
Because config files get committed to git by accident. Environment variables
don't live in the repo at all, so a secret can't leak by someone running
`git add .` on a tired Friday.

TIER 0 RULE (from docs/THREAT-MODEL.md)
Some values here are secrets. They must NEVER be returned by an API route,
written to a log line, or placed in an LLM's context window. The only safe
way to serialize this object is `public_dict()` below — read its comment to
see why it's built as an allowlist.
"""

# This import lets us write modern type hints (like `str | None`) even on
# older Python versions. It must be the first import. Harmless, standard.
from __future__ import annotations

import os                                    # gives access to environment variables
from dataclasses import dataclass, field     # tools for building tidy data objects
from urllib.parse import quote               # percent-encoding — the bug fix, see dsn()


# ═══════════════════════════════════════════════════════════════════════
#  HELPERS — read an environment variable and convert it safely
#
#  Environment variables are ALWAYS strings. Even SKY_MONTHLY_COST_CAP_USD=50
#  arrives as the text "50", not the number 50. These three helpers do the
#  conversion, and never crash if the value is missing or garbage.
# ═══════════════════════════════════════════════════════════════════════

def _env(key: str, default: str = "") -> str:
    """
    Read one environment variable as text.

    os.environ is a dictionary of everything the OS handed us.
    .get(key, default) means "give me this key, or `default` if it's absent"
    — this is why a missing variable returns "" instead of crashing.
    .strip() removes stray spaces and newlines, which sneak in constantly
    when values are pasted into a web form like Portainer's.

    The leading underscore in the name is a Python convention meaning
    "internal to this file — other modules shouldn't call this."
    """
    return os.environ.get(key, default).strip()


def _env_int(key: str, default: int) -> int:
    """
    Read an environment variable as a whole number.

    `_env(key) or default` uses a Python trick: an empty string "" is
    treated as False, so `"" or 5432` evaluates to 5432. If the variable
    exists, its text is used instead.

    The try/except catches the case where someone sets POSTGRES_PORT=banana.
    Rather than crashing the whole app on startup, we fall back to the
    default. Graceful degradation — see Risk #7 in the plan.
    """
    try:
        return int(_env(key) or default)
    except ValueError:
        return default


def _env_float(key: str, default: float) -> float:
    """Same as _env_int, but for decimals — e.g. a cost threshold of 0.75."""
    try:
        return float(_env(key) or default)
    except ValueError:
        return default


# ═══════════════════════════════════════════════════════════════════════
#  THE SETTINGS OBJECT
#
#  @dataclass tells Python: "this class is just a container for values —
#  write the boilerplate for me." Without it we'd hand-write an __init__
#  method assigning every field. With it, Python generates that.
#
#  frozen=True makes it READ-ONLY after creation. Any code that tries
#  `settings.pg_password = "hunter2"` raises an error instead of silently
#  succeeding. Config should be decided once at startup, not mutated at
#  runtime by whatever code happens to run last.
# ═══════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class Settings:

    # ─── Identity (decision DL-001) ───────────────────────────────────
    #
    # WHY `field(default_factory=lambda: ...)` INSTEAD OF PLAIN `= value`?
    #
    # A plain default is evaluated ONCE, when Python first reads this file.
    # default_factory takes a function and calls it when a Settings object
    # is actually created. `lambda: ...` is shorthand for a tiny throwaway
    # function.
    #
    # That distinction matters here: it guarantees we read the environment
    # at object-creation time, not at import time. Same reason you'd read a
    # trigger's payload when the flow runs, not when you saved the flow.

    identity_name: str = field(default_factory=lambda: _env("SKY_IDENTITY_NAME", "Sky Prime"))
    address_name: str = field(default_factory=lambda: _env("SKY_ADDRESS_NAME", "Sky"))
    env: str = field(default_factory=lambda: _env("SKY_ENV", "development"))
    version: str = field(default_factory=lambda: _env("SKY_VERSION", "0.1.0-phase0"))

    # ─── Gateway behaviour ────────────────────────────────────────────

    log_level: str = field(default_factory=lambda: _env("LOG_LEVEL", "INFO").upper())

    # Which websites are allowed to open a WebSocket to Sky.
    # The env var arrives as one comma-separated string:
    #     "https://a.com,https://b.com"
    # This splits it on commas, strips spaces from each piece, drops empties,
    # and freezes the result into a tuple (a list that can't be changed —
    # required because frozen dataclasses can't hold mutable values).
    allowed_origins: tuple[str, ...] = field(
        default_factory=lambda: tuple(
            o.strip() for o in _env("GATEWAY_ALLOWED_ORIGINS").split(",") if o.strip()
        )
    )

    # ─── Postgres connection details ──────────────────────────────────
    #
    # pg_host defaults to "postgres" — NOT localhost. Inside Docker, each
    # container gets a hostname matching its service name in the compose
    # file. From the gateway container, "postgres" resolves to the database
    # container. "localhost" would mean the gateway itself.

    pg_host: str = field(default_factory=lambda: _env("POSTGRES_HOST", "postgres"))
    pg_port: int = field(default_factory=lambda: _env_int("POSTGRES_PORT", 5432))
    pg_user: str = field(default_factory=lambda: _env("POSTGRES_USER", "sky"))
    pg_password: str = field(default_factory=lambda: _env("POSTGRES_PASSWORD"))  # 🔴 SECRET
    pg_db: str = field(default_factory=lambda: _env("POSTGRES_DB", "sky"))

    # ─── Cost guardrails (Risk #9 — cost drift) ───────────────────────
    #
    # A runaway agent loop can turn a $12/month hobby into a $180 surprise.
    # The gateway checks month-to-date spend against this cap before every
    # LLM call, and refuses once it's hit.

    monthly_cost_cap_usd: float = field(
        default_factory=lambda: _env_float("SKY_MONTHLY_COST_CAP_USD", 50.0)
    )
    cost_alert_threshold: float = field(
        default_factory=lambda: _env_float("SKY_COST_ALERT_THRESHOLD", 0.75)
    )

    # ─── Derived values ───────────────────────────────────────────────

    @property
    def dsn(self) -> str:
        """
        Build the database connection string.

        @property means you call this like an attribute — `settings.dsn`,
        not `settings.dsn()`. It looks like stored data but is computed
        fresh each time.

        A DSN ("Data Source Name") is just a URL describing where a
        database lives:

            postgresql://user:password@host:port/database

        🐛 THE BUG THIS LINE FIXES — 2026-08-07
        ─────────────────────────────────────────────────────────────
        We originally pasted the password straight into that URL. But a
        password generated by `openssl rand -base64 32` can contain the
        character `/`, and in a URL, `/` means "the address part is over,
        the path starts now."

        So this password:      W3ajW/Kp2x...
        produced this URL:     postgresql://sky:W3ajW/Kp2x...@postgres:5432/sky
        and the parser read:   host = "sky", port = "W3ajW"

        which blew up on `int("W3ajW")`, ten times, three seconds apart.

        quote() fixes it by PERCENT-ENCODING — replacing each unsafe
        character with a % and its hex code. `/` becomes %2F, `@` becomes
        %40, a space becomes %20. The parser then sees them as ordinary
        characters instead of structure.

        safe="" means "escape EVERYTHING, treat no character as special."
        By default quote() leaves `/` alone — which is exactly the
        character that broke us. The empty string is load-bearing.

        📌 GENERAL LESSON: never concatenate a value into a URL. Encode it.
        Same bug hits API calls when a parameter contains &, ?, # or a space.
        ─────────────────────────────────────────────────────────────
        """
        user = quote(self.pg_user, safe="")
        password = quote(self.pg_password, safe="")
        return f"postgresql://{user}:{password}@{self.pg_host}:{self.pg_port}/{self.pg_db}"

    def public_dict(self) -> dict:
        """
        The ONLY safe way to turn these settings into shareable data.

        This is an ALLOWLIST, not a denylist — and the difference is the
        whole point.

        A denylist says "return everything EXCEPT the password." That works
        until someone adds ANTHROPIC_API_KEY next month, forgets to add it
        to the exclusion list, and it starts appearing in /health responses.

        An allowlist says "return ONLY these five named things." A new
        secret added tomorrow is excluded automatically — not because
        anyone remembered, but because it simply isn't listed here.

        Security that depends on remembering isn't security.
        """
        return {
            "identity": self.identity_name,
            "address": self.address_name,
            "env": self.env,
            "version": self.version,
            "cost_cap_usd": self.monthly_cost_cap_usd,
        }


# ═══════════════════════════════════════════════════════════════════════
#  Create ONE Settings object when this file is first imported.
#
#  Everywhere else in the app does `from .config import settings` and gets
#  this same object. One source of truth, read from the environment once
#  at startup, immutable thereafter.
# ═══════════════════════════════════════════════════════════════════════

settings = Settings()
