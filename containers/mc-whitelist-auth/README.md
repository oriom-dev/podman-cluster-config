# mc-whitelist-auth

Minecraft access control service for Oriom.

## Required Secrets and How to Obtain Them

### BETTER_AUTH_SECRET
- Purpose: Better Auth session/signing secret.
- How to create:
  - `openssl rand -base64 48`
  - or `python -c "import secrets; print(secrets.token_urlsafe(48))"`
- Store in: `containers/mc-whitelist-auth/secrets.yaml` (`./bin/secret-edit.sh mc-whitelist-auth`).

### GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
- Purpose: Google sign-in for the admin/user portal.
- How to create:
  1. Open Google Cloud Console.
  2. Create/select a project.
  3. Configure OAuth consent screen.
  4. Create OAuth Client ID (Web application).
  5. Add redirect URI:
     - `https://mc.oriom.dev/api/auth/callback/google`
  6. Copy client ID and client secret.

### AUTHZ_API_TOKEN
- Purpose: Shared token between Velocity plugin and auth service for `/api/v1/authorize`.
- How to create:
  - `openssl rand -hex 32`
- Where to set:
  - `containers/mc-whitelist-auth/secrets.yaml` (`AUTHZ_API_TOKEN`)
  - the Velocity proxy that calls this API (not deployed from this repository yet;
    the previous `containers/mc-velocity` plugin is in Git history before its removal)

## Minecraft UUID Proof by One-Time Challenge Code

Microsoft account integration is removed.
When a player is denied by Velocity, plugin requests a one-time challenge from auth service and kicks with a short URL:

- `https://mc.oriom.dev/Ah9u4b`

### Challenge code policy
- Length: 6 characters
- Charset: excludes `0`, `O`, `I`, `l`
- Expiration: 10 minutes
- Usage: one-time only

### Runtime flow
1. Player connects to server host.
2. Velocity calls `/api/v1/authorize` with UUID, host, and API token.
3. If scope matches, auth service returns `allowed=true` and player is allowed.
4. If scope does not match, the same `/api/v1/authorize` call issues a one-time code and returns it.
5. Velocity shows `mc.oriom.dev/<code>` in kick message.
6. Player opens that URL and signs in with Google.
7. Service links Minecraft UUID and assigns domain scopes.

### Scope decision policy
Scope decision logic is implemented as a dedicated function to support future provider/policy extensions.

- Current default: allow attempted host domain with subdomains.
- Planned future: provider and policy can vary by attempted host.

## Non-secret but required
- `ADMIN_EMAIL_ALLOWLIST`: comma-separated admin emails.
- `DB_URL`: PostgreSQL connection string.
- `PUBLIC_BASE_URL` / `BETTER_AUTH_URL`: public URL (`https://mc.oriom.dev`).

### DB_URL
- `DB_URL` is a line in the `mc-whitelist-auth_env` envfile in
  `containers/mc-whitelist-auth/secrets.yaml` (the only secret this module loads), e.g.
  `DB_URL=postgresql://whitelist_auth:<strong-password>@mc-whitelist-db.ts.home.arpa:5432/defaultdb?sslmode=disable`

## Operational Notes
- This repository no longer exposes `/api/v1/whitelist`.
- Velocity integration endpoint: `/api/v1/authorize` (single endpoint; challenge code is issued here when denied)
