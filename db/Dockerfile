# ═══════════════════════════════════════════════════════════════════════
#  SKY — custom Postgres image
#
#  WHY THIS FILE EXISTS
#  Postgres runs any .sql file in /docker-entrypoint-initdb.d exactly once,
#  the first time it starts with an empty data directory. We originally
#  handed it those files with a bind mount — a folder shared from the host
#  into the container.
#
#  That broke. Portainer clones this repo to a path inside the Portainer
#  container, but Docker resolves bind mounts against the HOST filesystem.
#  The path didn't exist there, so Docker created an empty folder instead
#  of erroring, and Postgres initialized with no schema at all.
#
#  Baking the files into the image removes the host from the equation
#  entirely. The image carries its own schema. It behaves identically on
#  this Mac Pro, on a laptop, or on whatever replaces this hardware.
# ═══════════════════════════════════════════════════════════════════════

# Start from the official pgvector image — Postgres 17 with the vector
# extension already compiled in. We're not replacing it, we're adding to it.
FROM pgvector/pgvector:pg17

# Copy our SQL migrations into the folder Postgres checks on first boot.
# The build context is ./db (set in docker-compose.yml), so "init/" here
# means "db/init/" in the repo. Files run in ALPHABETICAL order — which is
# why they're numbered 001, 002, 003.
COPY init/ /docker-entrypoint-initdb.d/

# Make sure the postgres user inside the container can read them.
RUN chmod 0444 /docker-entrypoint-initdb.d/*.sql
