import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { z } from 'zod';

const envSchema = z.object({
  DB_URL: z.string().min(1, 'DB_URL is required.'),
  PUBLIC_BASE_URL: z.string().url('PUBLIC_BASE_URL must be a valid URL.'),
  BETTER_AUTH_URL: z.string().url('BETTER_AUTH_URL must be a valid URL.'),
  BETTER_AUTH_SECRET: z.string().min(1, 'BETTER_AUTH_SECRET is required.'),
  GOOGLE_CLIENT_ID: z.string().min(1, 'GOOGLE_CLIENT_ID is required.'),
  GOOGLE_CLIENT_SECRET: z.string().min(1, 'GOOGLE_CLIENT_SECRET is required.'),
  ADMIN_EMAIL_ALLOWLIST: z.string().min(1, 'ADMIN_EMAIL_ALLOWLIST is required.'),
  AUTHZ_API_TOKEN: z.string().min(1, 'AUTHZ_API_TOKEN is required.')
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  const lines = parsed.error.issues.map((issue) => {
    const key = issue.path.join('.') || 'ENV';
    return `- ${key}: ${issue.message}`;
  });

  throw new Error(`Invalid environment configuration:\n${lines.join('\n')}`);
}

export const env = parsed.data;