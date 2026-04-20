import { createRoute } from 'honox/factory';
import { auth } from '../../lib/auth';

export default createRoute(async (c) => {
  if (c.req.method !== 'POST') {
    return c.text('Method Not Allowed', 405);
  }

  return auth.api.signOut({
    headers: c.req.raw.headers,
    asResponse: true
  });
});
