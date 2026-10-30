import { createRoute } from 'honox/factory';
import { checkDatabase } from '../lib/db';

export default createRoute(async (c) => {
  try {
    await checkDatabase();
    return c.text('OK');
  } catch (error) {
    console.error('[mc-whitelist-auth] Health check failed', error);
    return c.text('Service Unavailable', 503);
  }
});
