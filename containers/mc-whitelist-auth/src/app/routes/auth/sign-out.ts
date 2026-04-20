import { createRoute } from 'honox/factory';
import { auth } from '../../lib/auth';

export const POST = createRoute(async (c) => {
  return auth.api.signOut({
    headers: c.req.raw.headers,
    asResponse: true
  });
});
