import { createRoute } from 'honox/factory';
import { appendAuditLog, authorizePlayerForHost, issueMinecraftAccessChallenge } from '../../../lib/db';
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
    const result = await authorizePlayerForHost(uuid, host);

    if (result.allowed) {
      void appendAuditLog({
        action: 'authorize_check',
        targetUserId: result.userId,
        metadata: {
          uuid,
          username,
          host,
          allowed: true,
          reason: result.reason
        }
      }).catch(() => {
        // Never block authorization response because of audit log failures.
      });

      return c.json(result);
    }

    if (result.reason === 'invalid_uuid' || result.reason === 'invalid_host') {
      return c.json(result, 400);
    }

    const challenge = await issueMinecraftAccessChallenge({
      uuidInput: uuid,
      hostInput: host,
      usernameInput: username
    });
    const shortUrl = `${trimTrailingSlash(env.PUBLIC_BASE_URL)}/${challenge.code}`;

    void appendAuditLog({
      action: 'authorize_check',
      targetUserId: result.userId,
      metadata: {
        uuid,
        username,
        host,
        allowed: false,
        reason: result.reason,
        challengeCode: challenge.code,
        challengeUrl: shortUrl,
        expiresAt: challenge.expiresAt.toISOString()
      }
    }).catch(() => {
      // Never block authorization response because of audit log failures.
    });

    return c.json({
      allowed: false,
      reason: result.reason,
      userId: result.userId,
      code: challenge.code,
      url: shortUrl,
      expiresAt: challenge.expiresAt.toISOString()
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Authorization failed';
    return c.json({ error: message }, 500);
  }
});
