import { createApp } from 'honox/server';
import { logger } from 'hono/logger';
import { auth } from './lib/auth';
import './lib/env';

const app = createApp({
  init: (hono) => {
    hono.use('*', logger());
    hono.on(['GET', 'POST'], '/api/auth/*', (c) => auth.handler(c.req.raw));
  }
});

export default app;
