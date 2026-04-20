# mc-whitelist-db

CockroachDB backend for mc-whitelist-auth.

## Security posture
- Runs in secure mode (not `--insecure`).
- SQL endpoint is exposed only in the DB tailscale sidecar namespace.
- Admin HTTP endpoint is bound to localhost only.
- App access uses username/password over TLS.

## Required SOPS secret entries
Set these entries in module secrets files:

- `containers/mc-whitelist-db/secrets.yaml`
	- key: `mc-whitelist-db_env`
	- value example: `DB_APP_PASSWORD=<strong-random-password>`

- `containers/mc-whitelist-auth/secrets.yaml`
	- key: `mc-whitelist-auth_db_env`
	- value example: `DB_URL=postgresql://whitelist_auth:<same-password>@mc-whitelist-db.ts.home.arpa:26258/defaultdb?sslmode=require`
