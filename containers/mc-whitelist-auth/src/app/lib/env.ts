import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { z } from 'zod';

const loadEnvFileIfPresent = (): void => {
  const envPath = resolve(process.cwd(), '.env');
  if (!existsSync(envPath)) {
    return;
  }

  const content = readFileSync(envPath, 'utf8');
  const lines = content.split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }

    const equalsIndex = trimmed.indexOf('=');
    if (equalsIndex <= 0) {
      continue;
    }

    const key = trimmed.slice(0, equalsIndex).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) || process.env[key] !== undefined) {
      continue;
    }

    let value = trimmed.slice(equalsIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    process.env[key] = value;
  }
};

loadEnvFileIfPresent();

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