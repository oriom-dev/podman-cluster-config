# mc-whitelist-db

PostgreSQL 17 backend for mc-whitelist-auth (replaced CockroachDB on 2026-11-07).

## Security posture
- Reachable only from containers on the `mc-whitelist` Podman network
  (alias `mc-whitelist-db.ts.home.arpa:5432`); no host port is published.
- Runs as the image's postgres user (uid 70) with a read-only root filesystem,
  no capabilities, `no-new-privileges`, and 256 MiB / 0.5 CPU limits.
- TLS is off: traffic never leaves the single-host bridge.

## Secrets
- `containers/mc-whitelist-db/secrets.yaml`, key `mc-whitelist-db_env`:
  `POSTGRES_PASSWORD=<password>`. Applied only when the volume is first
  initialised; to rotate, run `ALTER ROLE whitelist_auth PASSWORD '...'` and then
  update both secrets.
- `containers/mc-whitelist-auth/secrets.yaml`, key `mc-whitelist-auth_env`:
  `DB_URL=postgresql://whitelist_auth:<same password>@mc-whitelist-db.ts.home.arpa:5432/defaultdb?sslmode=disable`

The app creates its tables on start (`ensureSchema`).

## Data
- Volume `mc-whitelist-pg-data`; nightly `pg_dump` via `containers/backup`.
- The old CockroachDB volume `mc-whitelist-db-data` is kept for rollback only:
  `sudo podman volume rm mc-whitelist-db-data` once PostgreSQL is settled.
