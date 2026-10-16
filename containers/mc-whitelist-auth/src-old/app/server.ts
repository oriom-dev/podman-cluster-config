import { createApp } from 'honox/server';
import { logger } from 'hono/logger';
import { ensureSchema } from './lib/db';
import { auth } from './lib/auth';
import './lib/env';

const app = createApp({
  init: (hono) => {
    hono.use('*', logger());
    void ensureSchema().catch((error) => {
      console.error('[mc-whitelist-auth] Failed to initialize database schema', error);
    });
    hono.on(['GET', 'POST'], '/api/auth/*', (c) => auth.handler(c.req.raw));
  }
});

export default app;
