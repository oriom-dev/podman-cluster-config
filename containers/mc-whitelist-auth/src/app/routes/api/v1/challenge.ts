import { createRoute } from 'honox/factory';
import { appendAuditLog, issueMinecraftAccessChallenge } from '../../../lib/db';
import { env } from '../../../lib/env';

const trimTrailingSlash = (value: string): string => value.replace(/\/+$/, '');

export default createRoute(async (c) => {
  const expectedToken = env.AUTHZ_API_TOKEN;
  const providedToken = c.req.query('token') || c.req.header('x-api-token') || '';

  if (providedToken !== expectedToken) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const uuid = c.req.query('uuid') || '';
  const host = c.req.query('host') || c.req.query('domain') || c.req.header('x-minecraft-host') || '';
  const username = c.req.query('username') || c.req.header('x-minecraft-username') || '';

  if (!uuid || !host) {
    return c.json({ error: 'uuid and host are required' }, 400);
  }

  try {
    const challenge = await issueMinecraftAccessChallenge({
      uuidInput: uuid,
      hostInput: host,
      usernameInput: username
    });

    const shortUrl = `${trimTrailingSlash(env.PUBLIC_BASE_URL)}/${challenge.code}`;

    void appendAuditLog({
      action: 'access_challenge_issued',
      metadata: {
        code: challenge.code,
        uuid: challenge.playerUuid,
        username: challenge.playerUsername,
        host: challenge.attemptedHost,
        expiresAt: challenge.expiresAt.toISOString()
      }
    }).catch(() => {
      // Challenge issuance should not fail if audit logging fails.
    });

    return c.json({
      code: challenge.code,
      url: shortUrl,
      expiresAt: challenge.expiresAt.toISOString()
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to issue challenge code';
    return c.json({ error: message }, 400);
  }
});
