import { createRoute } from 'honox/factory';
import { appendAuditLog, authorizePlayerForHost } from '../../../lib/db';
import { env } from '../../../lib/env';

export default createRoute(async (c) => {
  const expectedToken = env.AUTHZ_API_TOKEN;

  const providedToken = c.req.query('token') || c.req.header('x-api-token') || '';
  if (providedToken !== expectedToken) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const uuid = c.req.query('uuid') || '';
  const host = c.req.query('host') || c.req.query('domain') || c.req.header('x-minecraft-host') || '';
  if (!uuid || !host) {
    return c.json({ error: 'uuid and host are required' }, 400);
  }

  const result = await authorizePlayerForHost(uuid, host);

  void appendAuditLog({
    action: 'authorize_check',
    targetUserId: result.userId,
    metadata: {
      uuid,
      host,
      allowed: result.allowed,
      reason: result.reason
    }
  }).catch(() => {
    // Never block authorization response because of audit log failures.
  });

  return c.json(result);
});
