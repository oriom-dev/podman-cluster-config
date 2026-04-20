# mc-whitelist-auth

Minecraft access control service for Oriom.

## Required Secrets and How to Obtain Them

### BETTER_AUTH_SECRET
- Purpose: Better Auth session/signing secret.
- How to create:
  - `openssl rand -base64 48`
  - or `python -c "import secrets; print(secrets.token_urlsafe(48))"`
- Store in: `containers/mc-whitelist-auth/mc-whitelist-auth.container.in` (or your SOPS secret source).

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
  - `containers/mc-whitelist-auth/mc-whitelist-auth.container.in` (`AUTHZ_API_TOKEN`)
  - `containers/mc-velocity/mc-velocity.container` (`AUTHZ_API_TOKEN`)

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
2. Velocity checks `/api/v1/authorize`.
3. If denied, Velocity calls `/api/v1/challenge` and gets short URL.
4. Player opens the URL and signs in with Google.
5. Service links Minecraft UUID and assigns domain scopes.

### Scope decision policy
Scope decision logic is implemented as a dedicated function to support future provider/policy extensions.

- Current default: allow attempted host domain with subdomains.
- Planned future: provider and policy can vary by attempted host.

## Non-secret but required
- `ADMIN_EMAIL_ALLOWLIST`: comma-separated admin emails.
- `DB_URL`: CockroachDB connection string.
- `PUBLIC_BASE_URL` / `BETTER_AUTH_URL`: public URL (`https://mc.oriom.dev`).

## Operational Notes
- This repository no longer exposes `/api/v1/whitelist`.
- Authorization check endpoint: `/api/v1/authorize`
- Challenge issuance endpoint: `/api/v1/challenge`
