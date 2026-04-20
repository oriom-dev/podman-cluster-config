import { and, asc, desc, eq, gt, isNull, or, sql } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/node-postgres';
import { boolean, index, pgTable, primaryKey, text, timestamp, uniqueIndex } from 'drizzle-orm/pg-core';
import { lookup } from 'node:dns/promises';
import { readFile } from 'node:fs/promises';
import { Pool } from 'pg';
import { env } from './env';

export const authUsers = pgTable(
  'user',
  {
    id: text('id').primaryKey(),
    name: text('name').notNull(),
    email: text('email').notNull(),
    emailVerified: boolean('emailVerified').notNull().default(false),
    image: text('image'),
    createdAt: timestamp('createdAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
    updatedAt: timestamp('updatedAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow()
  },
  (table) => [uniqueIndex('user_email_unique').on(table.email)]
);

export const authSessions = pgTable(
  'session',
  {
    id: text('id').primaryKey(),
    expiresAt: timestamp('expiresAt', { withTimezone: true, mode: 'date' }).notNull(),
    token: text('token').notNull(),
    createdAt: timestamp('createdAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
    updatedAt: timestamp('updatedAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
    ipAddress: text('ipAddress'),
    userAgent: text('userAgent'),
    userId: text('userId')
      .notNull()
      .references(() => authUsers.id, { onDelete: 'cascade' })
  },
  (table) => [uniqueIndex('session_token_unique').on(table.token), index('session_user_id_idx').on(table.userId)]
);

export const authAccounts = pgTable(
  'account',
  {
    id: text('id').primaryKey(),
    accountId: text('accountId').notNull(),
    providerId: text('providerId').notNull(),
    userId: text('userId')
      .notNull()
      .references(() => authUsers.id, { onDelete: 'cascade' }),
    accessToken: text('accessToken'),
    refreshToken: text('refreshToken'),
    idToken: text('idToken'),
    accessTokenExpiresAt: timestamp('accessTokenExpiresAt', { withTimezone: true, mode: 'date' }),
    refreshTokenExpiresAt: timestamp('refreshTokenExpiresAt', { withTimezone: true, mode: 'date' }),
    scope: text('scope'),
    password: text('password'),
    createdAt: timestamp('createdAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
    updatedAt: timestamp('updatedAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow()
  },
  (table) => [
    uniqueIndex('account_provider_account_unique').on(table.providerId, table.accountId),
    index('account_user_id_idx').on(table.userId)
  ]
);

export const authVerifications = pgTable(
  'verification',
  {
    id: text('id').primaryKey(),
    identifier: text('identifier').notNull(),
    value: text('value').notNull(),
    expiresAt: timestamp('expiresAt', { withTimezone: true, mode: 'date' }).notNull(),
    createdAt: timestamp('createdAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
    updatedAt: timestamp('updatedAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow()
  },
  (table) => [index('verification_identifier_idx').on(table.identifier)]
);

export const minecraftPlayerLinks = pgTable(
  'minecraft_player_link',
  {
    uuid: text('uuid').primaryKey(),
    username: text('username').notNull(),
    userId: text('userId')
      .notNull()
      .references(() => authUsers.id, { onDelete: 'cascade' }),
    createdAt: timestamp('createdAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
    updatedAt: timestamp('updatedAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow()
  },
  (table) => [index('minecraft_player_link_user_id_idx').on(table.userId)]
);

export const minecraftAccessChallenges = pgTable(
  'minecraft_access_challenge',
  {
    code: text('code').primaryKey(),
    playerUuid: text('playerUuid').notNull(),
    playerUsername: text('playerUsername').notNull(),
    attemptedHost: text('attemptedHost').notNull(),
    createdAt: timestamp('createdAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
    expiresAt: timestamp('expiresAt', { withTimezone: true, mode: 'date' }).notNull(),
    consumedAt: timestamp('consumedAt', { withTimezone: true, mode: 'date' }),
    consumedByUserId: text('consumedByUserId').references(() => authUsers.id, { onDelete: 'set null' })
  },
  (table) => [
    index('minecraft_access_challenge_expires_at_idx').on(table.expiresAt),
    index('minecraft_access_challenge_attempted_host_idx').on(table.attemptedHost),
    index('minecraft_access_challenge_player_uuid_idx').on(table.playerUuid)
  ]
);

export const userDomainGrants = pgTable(
  'user_domain_grant',
  {
    userId: text('userId')
      .notNull()
      .references(() => authUsers.id, { onDelete: 'cascade' }),
    domain: text('domain').notNull(),
    includeSubdomains: boolean('includeSubdomains').notNull().default(true),
    createdAt: timestamp('createdAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
    updatedAt: timestamp('updatedAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow()
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.domain], name: 'user_domain_grant_pk' }),
    index('user_domain_grant_user_id_idx').on(table.userId)
  ]
);

export const auditLogs = pgTable(
  'audit_log',
  {
    id: text('id').primaryKey(),
    action: text('action').notNull(),
    actorUserId: text('actorUserId'),
    actorEmail: text('actorEmail'),
    targetUserId: text('targetUserId'),
    targetEmail: text('targetEmail'),
    metadata: text('metadata').notNull().default('{}'),
    createdAt: timestamp('createdAt', { withTimezone: true, mode: 'date' }).notNull().defaultNow()
  },
  (table) => [index('audit_log_created_at_idx').on(table.createdAt), index('audit_log_action_idx').on(table.action)]
);

export const schema = {
  user: authUsers,
  session: authSessions,
  account: authAccounts,
  verification: authVerifications,
  minecraftPlayerLinks,
  minecraftAccessChallenges,
  userDomainGrants,
  auditLogs
};

const normalizeDbConnectionString = (
  rawConnectionString: string
): {
  connectionString: string;
  parsedUrl: URL | null;
  normalizedToLibpqCompat: boolean;
} => {
  try {
    const parsedUrl = new URL(rawConnectionString);
    const sslMode = (parsedUrl.searchParams.get('sslmode') || '').toLowerCase();
    const hasLibpqCompat = parsedUrl.searchParams.has('uselibpqcompat');

    if (sslMode === 'require' && !hasLibpqCompat) {
      parsedUrl.searchParams.set('uselibpqcompat', 'true');
      return {
        connectionString: parsedUrl.toString(),
        parsedUrl,
        normalizedToLibpqCompat: true
      };
    }

    return {
      connectionString: parsedUrl.toString(),
      parsedUrl,
      normalizedToLibpqCompat: false
    };
  } catch {
    return {
      connectionString: rawConnectionString,
      parsedUrl: null,
      normalizedToLibpqCompat: false
    };
  }
};

const normalizedConnection = normalizeDbConnectionString(env.DB_URL);
const connectionString = normalizedConnection.connectionString;
const parsedConnectionUrl = normalizedConnection.parsedUrl;

if (normalizedConnection.normalizedToLibpqCompat) {
  console.info(
    '[mc-whitelist-auth] Added uselibpqcompat=true to DB_URL for sslmode=require to use libpq-compatible TLS semantics.'
  );
}

const pool = new Pool({
  connectionString,
  max: 5
});

export const db = drizzle(pool, { schema });

let schemaPromise: Promise<void> | null = null;

export type DbRuntimeDiagnostics = {
  dbHost: string | null;
  dbPort: string | null;
  dbProtocol: string | null;
  dbSslMode: string | null;
  dbUseLibpqCompat: string | null;
  lookupV4: string[];
  lookupV6: string[];
  lookupV4Error: string | null;
  lookupV6Error: string | null;
  lookupError: string | null;
  resolvConfHead: string[];
  resolvConfError: string | null;
};

const lookupByFamily = async (
  host: string,
  family: 4 | 6
): Promise<{ addresses: string[]; error: string | null }> => {
  try {
    const records = await lookup(host, { family, all: true });
    return { addresses: records.map((item) => item.address), error: null };
  } catch (error) {
    return {
      addresses: [],
      error: error instanceof Error ? error.message : `unknown IPv${family} lookup error`
    };
  }
};

const readResolvConfHead = async (): Promise<{ lines: string[]; error: string | null }> => {
  try {
    const content = await readFile('/etc/resolv.conf', 'utf8');
    const lines = content
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean)
      .slice(0, 8);
    return { lines, error: null };
  } catch (error) {
    return {
      lines: [],
      error: error instanceof Error ? error.message : 'unknown error reading /etc/resolv.conf'
    };
  }
};

export const getDbRuntimeDiagnostics = async (): Promise<DbRuntimeDiagnostics> => {
  const dbHost = parsedConnectionUrl?.hostname ?? null;
  const dbPort = parsedConnectionUrl?.port || null;
  const dbProtocol = parsedConnectionUrl?.protocol ?? null;
  const dbSslMode = parsedConnectionUrl?.searchParams.get('sslmode') ?? null;
  const dbUseLibpqCompat = parsedConnectionUrl?.searchParams.get('uselibpqcompat') ?? null;
  const resolvConf = await readResolvConfHead();

  if (!dbHost) {
    return {
      dbHost,
      dbPort,
      dbProtocol,
      dbSslMode,
      dbUseLibpqCompat,
      lookupV4: [],
      lookupV6: [],
      lookupV4Error: null,
      lookupV6Error: null,
      lookupError: 'DB_URL host is missing or invalid',
      resolvConfHead: resolvConf.lines,
      resolvConfError: resolvConf.error
    };
  }

  const [v4, v6] = await Promise.all([lookupByFamily(dbHost, 4), lookupByFamily(dbHost, 6)]);
  const lookupError =
    v4.addresses.length === 0 && v6.addresses.length === 0
      ? [v4.error, v6.error].filter(Boolean).join(' | ') || 'no DNS records found'
      : null;

  return {
    dbHost,
    dbPort,
    dbProtocol,
    dbSslMode,
    dbUseLibpqCompat,
    lookupV4: v4.addresses,
    lookupV6: v6.addresses,
    lookupV4Error: v4.error,
    lookupV6Error: v6.error,
    lookupError,
    resolvConfHead: resolvConf.lines,
    resolvConfError: resolvConf.error
  };
};

export const ensureSchema = async (): Promise<void> => {
  if (schemaPromise) {
    return schemaPromise;
  }

  schemaPromise = (async () => {
    const client = await pool.connect();

    try {
      await client.query(`
        CREATE TABLE IF NOT EXISTS "user" (
          "id" STRING PRIMARY KEY,
          "name" STRING NOT NULL,
          "email" STRING NOT NULL,
          "emailVerified" BOOL NOT NULL DEFAULT false,
          "image" STRING,
          "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `);

      await client.query('CREATE UNIQUE INDEX IF NOT EXISTS user_email_unique ON "user" ("email")');

      await client.query(`
        CREATE TABLE IF NOT EXISTS "session" (
          "id" STRING PRIMARY KEY,
          "expiresAt" TIMESTAMPTZ NOT NULL,
          "token" STRING NOT NULL,
          "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          "ipAddress" STRING,
          "userAgent" STRING,
          "userId" STRING NOT NULL REFERENCES "user"("id") ON DELETE CASCADE
        )
      `);

      await client.query('CREATE UNIQUE INDEX IF NOT EXISTS session_token_unique ON "session" ("token")');
      await client.query('CREATE INDEX IF NOT EXISTS session_user_id_idx ON "session" ("userId")');

      await client.query(`
        CREATE TABLE IF NOT EXISTS "account" (
          "id" STRING PRIMARY KEY,
          "accountId" STRING NOT NULL,
          "providerId" STRING NOT NULL,
          "userId" STRING NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
          "accessToken" STRING,
          "refreshToken" STRING,
          "idToken" STRING,
          "accessTokenExpiresAt" TIMESTAMPTZ,
          "refreshTokenExpiresAt" TIMESTAMPTZ,
          "scope" STRING,
          "password" STRING,
          "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `);

      await client.query(
        'CREATE UNIQUE INDEX IF NOT EXISTS account_provider_account_unique ON "account" ("providerId", "accountId")'
      );
      await client.query('CREATE INDEX IF NOT EXISTS account_user_id_idx ON "account" ("userId")');

      await client.query(`
        CREATE TABLE IF NOT EXISTS "verification" (
          "id" STRING PRIMARY KEY,
          "identifier" STRING NOT NULL,
          "value" STRING NOT NULL,
          "expiresAt" TIMESTAMPTZ NOT NULL,
          "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `);

      await client.query(
        'CREATE INDEX IF NOT EXISTS verification_identifier_idx ON "verification" ("identifier")'
      );

      await client.query(`
        CREATE TABLE IF NOT EXISTS "minecraft_player_link" (
          "uuid" STRING PRIMARY KEY,
          "username" STRING NOT NULL,
          "userId" STRING NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
          "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `);

      await client.query(
        'CREATE INDEX IF NOT EXISTS minecraft_player_link_user_id_idx ON "minecraft_player_link" ("userId")'
      );

      await client.query(`
        CREATE TABLE IF NOT EXISTS "minecraft_access_challenge" (
          "code" STRING PRIMARY KEY,
          "playerUuid" STRING NOT NULL,
          "playerUsername" STRING NOT NULL,
          "attemptedHost" STRING NOT NULL,
          "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          "expiresAt" TIMESTAMPTZ NOT NULL,
          "consumedAt" TIMESTAMPTZ,
          "consumedByUserId" STRING REFERENCES "user"("id") ON DELETE SET NULL
        )
      `);

      await client.query(
        'CREATE INDEX IF NOT EXISTS minecraft_access_challenge_expires_at_idx ON "minecraft_access_challenge" ("expiresAt")'
      );
      await client.query(
        'CREATE INDEX IF NOT EXISTS minecraft_access_challenge_attempted_host_idx ON "minecraft_access_challenge" ("attemptedHost")'
      );
      await client.query(
        'CREATE INDEX IF NOT EXISTS minecraft_access_challenge_player_uuid_idx ON "minecraft_access_challenge" ("playerUuid")'
      );

      await client.query(`
        CREATE TABLE IF NOT EXISTS "user_domain_grant" (
          "userId" STRING NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
          "domain" STRING NOT NULL,
          "includeSubdomains" BOOL NOT NULL DEFAULT true,
          "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
          CONSTRAINT "user_domain_grant_pk" PRIMARY KEY ("userId", "domain")
        )
      `);

      await client.query(
        'CREATE INDEX IF NOT EXISTS user_domain_grant_user_id_idx ON "user_domain_grant" ("userId")'
      );

      await client.query(`
        CREATE TABLE IF NOT EXISTS "audit_log" (
          "id" STRING PRIMARY KEY,
          "action" STRING NOT NULL,
          "actorUserId" STRING,
          "actorEmail" STRING,
          "targetUserId" STRING,
          "targetEmail" STRING,
          "metadata" STRING NOT NULL DEFAULT '{}',
          "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `);

      await client.query('CREATE INDEX IF NOT EXISTS audit_log_created_at_idx ON "audit_log" ("createdAt")');
      await client.query('CREATE INDEX IF NOT EXISTS audit_log_action_idx ON "audit_log" ("action")');
    } finally {
      client.release();
    }
  })().catch((error) => {
    // Allow retry on transient failures such as DNS race conditions at startup.
    schemaPromise = null;
    throw error;
  });

  return schemaPromise;
};

export type DomainGrant = {
  userId: string;
  domain: string;
  includeSubdomains: boolean;
};

export type MinecraftPlayerLink = {
  uuid: string;
  username: string;
  userId: string;
};

export type AuditLogRecord = {
  id: string;
  action: string;
  actorUserId: string | null;
  actorEmail: string | null;
  targetUserId: string | null;
  targetEmail: string | null;
  metadata: string;
  createdAt: Date;
};

export type MinecraftAccessChallenge = {
  code: string;
  playerUuid: string;
  playerUsername: string;
  attemptedHost: string;
  createdAt: Date;
  expiresAt: Date;
  consumedAt: Date | null;
  consumedByUserId: string | null;
};

export type ConsumeMinecraftAccessChallengeResult = {
  status: 'consumed' | 'not_found' | 'expired' | 'already_used';
  challenge?: MinecraftAccessChallenge;
};

const CHALLENGE_CODE_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
const CHALLENGE_CODE_LENGTH = 6;
const CHALLENGE_CODE_TTL_MS = 10 * 60 * 1000;
const CHALLENGE_CODE_REGEX = /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]{6}$/;

const randomInt = (maxExclusive: number): number => {
  if (typeof globalThis.crypto?.getRandomValues === 'function') {
    const array = new Uint32Array(1);
    globalThis.crypto.getRandomValues(array);
    return array[0] % maxExclusive;
  }

  return Math.floor(Math.random() * maxExclusive);
};

const createChallengeCode = (): string => {
  let code = '';

  for (let index = 0; index < CHALLENGE_CODE_LENGTH; index += 1) {
    code += CHALLENGE_CODE_ALPHABET[randomInt(CHALLENGE_CODE_ALPHABET.length)];
  }

  return code;
};

export const normalizeChallengeCode = (value: string): string | null => {
  const code = value.trim();
  return CHALLENGE_CODE_REGEX.test(code) ? code : null;
};

export const normalizePlayerUuid = (value: string): string | null => {
  const compact = value.trim().toLowerCase().replace(/-/g, '');
  if (!/^[0-9a-f]{32}$/.test(compact)) {
    return null;
  }

  return `${compact.slice(0, 8)}-${compact.slice(8, 12)}-${compact.slice(12, 16)}-${compact.slice(16, 20)}-${compact.slice(20)}`;
};

export const normalizeDomain = (value: string): string | null => {
  const normalized = value.trim().toLowerCase().replace(/\.$/, '');
  if (!normalized || normalized.startsWith('.') || normalized.endsWith('.') || normalized.includes('..')) {
    return null;
  }

  if (!/^[a-z0-9.-]+$/.test(normalized)) {
    return null;
  }

  return normalized;
};

export const isAdminEmail = (email: string | null | undefined): boolean => {
  if (!email) {
    return false;
  }

  const allowlist = env.ADMIN_EMAIL_ALLOWLIST
    .split(',')
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean);

  return allowlist.includes(email.trim().toLowerCase());
};

export const upsertMinecraftPlayerForUser = async (
  userId: string,
  uuidInput: string,
  usernameInput: string
): Promise<{ uuid: string; username: string }> => {
  await ensureSchema();

  const uuid = normalizePlayerUuid(uuidInput);
  if (!uuid) {
    throw new Error('Minecraft UUID must be 32 hex chars (with or without hyphens).');
  }

  const username = usernameInput.trim();
  if (!username || username.length > 16) {
    throw new Error('Minecraft username is required and must be 16 chars or less.');
  }

  await db
    .insert(minecraftPlayerLinks)
    .values({
      uuid,
      username,
      userId,
      updatedAt: new Date()
    })
    .onConflictDoUpdate({
      target: minecraftPlayerLinks.uuid,
      set: {
        userId,
        username,
        updatedAt: new Date()
      }
    });

  return { uuid, username };
};

export const listMinecraftPlayersForUser = async (userId: string): Promise<MinecraftPlayerLink[]> => {
  await ensureSchema();
  return db
    .select({
      uuid: minecraftPlayerLinks.uuid,
      username: minecraftPlayerLinks.username,
      userId: minecraftPlayerLinks.userId
    })
    .from(minecraftPlayerLinks)
    .where(eq(minecraftPlayerLinks.userId, userId))
    .orderBy(asc(minecraftPlayerLinks.username));
};

export const issueMinecraftAccessChallenge = async (params: {
  uuidInput: string;
  hostInput: string;
  usernameInput?: string;
}): Promise<MinecraftAccessChallenge> => {
  await ensureSchema();

  const playerUuid = normalizePlayerUuid(params.uuidInput);
  if (!playerUuid) {
    throw new Error('Minecraft UUID must be 32 hex chars (with or without hyphens).');
  }

  const attemptedHost = normalizeDomain(params.hostInput);
  if (!attemptedHost) {
    throw new Error('Host must be a valid hostname.');
  }

  const providedUsername = `${params.usernameInput ?? ''}`.trim();
  const playerUsername =
    providedUsername.length > 0
      ? providedUsername.slice(0, 16)
      : `mc-${playerUuid.replace(/-/g, '').slice(0, 12)}`;

  const expiresAt = new Date(Date.now() + CHALLENGE_CODE_TTL_MS);

  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = createChallengeCode();

    const inserted = await db
      .insert(minecraftAccessChallenges)
      .values({
        code,
        playerUuid,
        playerUsername,
        attemptedHost,
        expiresAt,
        consumedAt: null,
        consumedByUserId: null
      })
      .onConflictDoNothing()
      .returning({
        code: minecraftAccessChallenges.code,
        playerUuid: minecraftAccessChallenges.playerUuid,
        playerUsername: minecraftAccessChallenges.playerUsername,
        attemptedHost: minecraftAccessChallenges.attemptedHost,
        createdAt: minecraftAccessChallenges.createdAt,
        expiresAt: minecraftAccessChallenges.expiresAt,
        consumedAt: minecraftAccessChallenges.consumedAt,
        consumedByUserId: minecraftAccessChallenges.consumedByUserId
      });

    if (inserted[0]) {
      return inserted[0];
    }
  }

  throw new Error('Failed to issue access challenge code. Please retry.');
};

export const findMinecraftAccessChallengeByCode = async (
  codeInput: string
): Promise<MinecraftAccessChallenge | null> => {
  await ensureSchema();

  const code = normalizeChallengeCode(codeInput);
  if (!code) {
    return null;
  }

  const rows = await db
    .select({
      code: minecraftAccessChallenges.code,
      playerUuid: minecraftAccessChallenges.playerUuid,
      playerUsername: minecraftAccessChallenges.playerUsername,
      attemptedHost: minecraftAccessChallenges.attemptedHost,
      createdAt: minecraftAccessChallenges.createdAt,
      expiresAt: minecraftAccessChallenges.expiresAt,
      consumedAt: minecraftAccessChallenges.consumedAt,
      consumedByUserId: minecraftAccessChallenges.consumedByUserId
    })
    .from(minecraftAccessChallenges)
    .where(eq(minecraftAccessChallenges.code, code))
    .limit(1);

  return rows[0] ?? null;
};

export const consumeMinecraftAccessChallengeForUser = async (
  codeInput: string,
  userId: string
): Promise<ConsumeMinecraftAccessChallengeResult> => {
  await ensureSchema();

  const code = normalizeChallengeCode(codeInput);
  if (!code) {
    return { status: 'not_found' };
  }

  const now = new Date();
  const current = await findMinecraftAccessChallengeByCode(code);

  if (!current) {
    return { status: 'not_found' };
  }

  if (current.consumedAt) {
    return { status: 'already_used', challenge: current };
  }

  if (current.expiresAt.getTime() <= now.getTime()) {
    return { status: 'expired', challenge: current };
  }

  const updated = await db
    .update(minecraftAccessChallenges)
    .set({
      consumedAt: now,
      consumedByUserId: userId
    })
    .where(
      and(
        eq(minecraftAccessChallenges.code, code),
        isNull(minecraftAccessChallenges.consumedAt),
        gt(minecraftAccessChallenges.expiresAt, now)
      )
    )
    .returning({
      code: minecraftAccessChallenges.code,
      playerUuid: minecraftAccessChallenges.playerUuid,
      playerUsername: minecraftAccessChallenges.playerUsername,
      attemptedHost: minecraftAccessChallenges.attemptedHost,
      createdAt: minecraftAccessChallenges.createdAt,
      expiresAt: minecraftAccessChallenges.expiresAt,
      consumedAt: minecraftAccessChallenges.consumedAt,
      consumedByUserId: minecraftAccessChallenges.consumedByUserId
    });

  if (updated[0]) {
    return { status: 'consumed', challenge: updated[0] };
  }

  const latest = await findMinecraftAccessChallengeByCode(code);
  if (!latest) {
    return { status: 'not_found' };
  }

  if (latest.consumedAt) {
    return { status: 'already_used', challenge: latest };
  }

  if (latest.expiresAt.getTime() <= now.getTime()) {
    return { status: 'expired', challenge: latest };
  }

  return { status: 'already_used', challenge: latest };
};

export const listAllMinecraftPlayersWithUsers = async (): Promise<
  Array<{ uuid: string; username: string; email: string; userId: string }>
> => {
  await ensureSchema();
  return db
    .select({
      uuid: minecraftPlayerLinks.uuid,
      username: minecraftPlayerLinks.username,
      userId: minecraftPlayerLinks.userId,
      email: authUsers.email
    })
    .from(minecraftPlayerLinks)
    .innerJoin(authUsers, eq(minecraftPlayerLinks.userId, authUsers.id))
    .orderBy(asc(authUsers.email), asc(minecraftPlayerLinks.username));
};

export const listUsers = async (): Promise<Array<{ id: string; email: string; name: string }>> => {
  await ensureSchema();
  return db
    .select({
      id: authUsers.id,
      email: authUsers.email,
      name: authUsers.name
    })
    .from(authUsers)
    .orderBy(asc(authUsers.email));
};

export const searchUsers = async (
  queryInput: string,
  limit = 40
): Promise<Array<{ id: string; email: string; name: string }>> => {
  await ensureSchema();

  const query = queryInput.trim().toLowerCase();
  if (!query) {
    return listUsers();
  }

  const pattern = `%${query}%`;

  return db
    .select({
      id: authUsers.id,
      email: authUsers.email,
      name: authUsers.name
    })
    .from(authUsers)
    .where(
      or(
        sql<boolean>`lower(${authUsers.email}) LIKE ${pattern}`,
        sql<boolean>`lower(${authUsers.name}) LIKE ${pattern}`
      )
    )
    .orderBy(asc(authUsers.email))
    .limit(Math.max(1, Math.min(limit, 100)));
};

const createAuditLogId = (): string => {
  if (typeof globalThis.crypto?.randomUUID === 'function') {
    return globalThis.crypto.randomUUID();
  }

  return `log-${Date.now()}-${Math.random().toString(16).slice(2)}`;
};

export const appendAuditLog = async (entry: {
  action: string;
  actorUserId?: string | null;
  actorEmail?: string | null;
  targetUserId?: string | null;
  targetEmail?: string | null;
  metadata?: Record<string, unknown>;
}): Promise<void> => {
  await ensureSchema();

  const action = entry.action.trim();
  if (!action) {
    throw new Error('Audit log action is required.');
  }

  await db.insert(auditLogs).values({
    id: createAuditLogId(),
    action,
    actorUserId: entry.actorUserId ?? null,
    actorEmail: entry.actorEmail ?? null,
    targetUserId: entry.targetUserId ?? null,
    targetEmail: entry.targetEmail ?? null,
    metadata: JSON.stringify(entry.metadata ?? {}),
    createdAt: new Date()
  });
};

export const listAuditLogs = async (queryInput: string, limit = 150): Promise<AuditLogRecord[]> => {
  await ensureSchema();

  const query = queryInput.trim().toLowerCase();
  const cappedLimit = Math.max(1, Math.min(limit, 400));

  if (!query) {
    return db
      .select({
        id: auditLogs.id,
        action: auditLogs.action,
        actorUserId: auditLogs.actorUserId,
        actorEmail: auditLogs.actorEmail,
        targetUserId: auditLogs.targetUserId,
        targetEmail: auditLogs.targetEmail,
        metadata: auditLogs.metadata,
        createdAt: auditLogs.createdAt
      })
      .from(auditLogs)
      .orderBy(desc(auditLogs.createdAt))
      .limit(cappedLimit);
  }

  const pattern = `%${query}%`;

  return db
    .select({
      id: auditLogs.id,
      action: auditLogs.action,
      actorUserId: auditLogs.actorUserId,
      actorEmail: auditLogs.actorEmail,
      targetUserId: auditLogs.targetUserId,
      targetEmail: auditLogs.targetEmail,
      metadata: auditLogs.metadata,
      createdAt: auditLogs.createdAt
    })
    .from(auditLogs)
    .where(
      or(
        sql<boolean>`lower(${auditLogs.action}) LIKE ${pattern}`,
        sql<boolean>`lower(coalesce(${auditLogs.actorEmail}, '')) LIKE ${pattern}`,
        sql<boolean>`lower(coalesce(${auditLogs.targetEmail}, '')) LIKE ${pattern}`,
        sql<boolean>`lower(${auditLogs.metadata}) LIKE ${pattern}`
      )
    )
    .orderBy(desc(auditLogs.createdAt))
    .limit(cappedLimit);
};

export const findUserByEmail = async (emailInput: string): Promise<{ id: string; email: string; name: string } | null> => {
  await ensureSchema();

  const email = emailInput.trim().toLowerCase();
  if (!email) {
    return null;
  }

  const rows = await db
    .select({
      id: authUsers.id,
      email: authUsers.email,
      name: authUsers.name
    })
    .from(authUsers)
    .where(eq(authUsers.email, email))
    .limit(1);

  return rows[0] ?? null;
};

export const upsertDomainGrantForUser = async (
  userId: string,
  domainInput: string,
  includeSubdomains: boolean
): Promise<DomainGrant> => {
  await ensureSchema();

  const domain = normalizeDomain(domainInput);
  if (!domain) {
    throw new Error('Domain must be a valid hostname (for example: oriom.dev).');
  }

  await db
    .insert(userDomainGrants)
    .values({
      userId,
      domain,
      includeSubdomains,
      updatedAt: new Date()
    })
    .onConflictDoUpdate({
      target: [userDomainGrants.userId, userDomainGrants.domain],
      set: {
        includeSubdomains,
        updatedAt: new Date()
      }
    });

  return {
    userId,
    domain,
    includeSubdomains
  };
};

export const revokeDomainGrantForUser = async (userId: string, domainInput: string): Promise<void> => {
  await ensureSchema();

  const domain = normalizeDomain(domainInput);
  if (!domain) {
    throw new Error('Domain format is invalid.');
  }

  await db
    .delete(userDomainGrants)
    .where(and(eq(userDomainGrants.userId, userId), eq(userDomainGrants.domain, domain)));
};

export const listDomainGrantsForUser = async (userId: string): Promise<DomainGrant[]> => {
  await ensureSchema();

  return db
    .select({
      userId: userDomainGrants.userId,
      domain: userDomainGrants.domain,
      includeSubdomains: userDomainGrants.includeSubdomains
    })
    .from(userDomainGrants)
    .where(eq(userDomainGrants.userId, userId))
    .orderBy(asc(userDomainGrants.domain));
};

export const listAllDomainGrantsWithUsers = async (): Promise<
  Array<{ userId: string; email: string; domain: string; includeSubdomains: boolean }>
> => {
  await ensureSchema();

  return db
    .select({
      userId: userDomainGrants.userId,
      email: authUsers.email,
      domain: userDomainGrants.domain,
      includeSubdomains: userDomainGrants.includeSubdomains
    })
    .from(userDomainGrants)
    .innerJoin(authUsers, eq(userDomainGrants.userId, authUsers.id))
    .orderBy(asc(authUsers.email), asc(userDomainGrants.domain));
};

const hostMatchesDomain = (host: string, domain: string, includeSubdomains: boolean): boolean => {
  if (host === domain) {
    return true;
  }

  if (!includeSubdomains) {
    return false;
  }

  return host.endsWith(`.${domain}`);
};

export const authorizePlayerForHost = async (
  uuidInput: string,
  hostInput: string
): Promise<{ allowed: boolean; reason: string; userId?: string }> => {
  await ensureSchema();

  const uuid = normalizePlayerUuid(uuidInput);
  if (!uuid) {
    return { allowed: false, reason: 'invalid_uuid' };
  }

  const host = normalizeDomain(hostInput);
  if (!host) {
    return { allowed: false, reason: 'invalid_host' };
  }

  const players = await db
    .select({
      userId: minecraftPlayerLinks.userId
    })
    .from(minecraftPlayerLinks)
    .where(eq(minecraftPlayerLinks.uuid, uuid))
    .limit(1);

  const player = players[0];
  if (!player) {
    return { allowed: false, reason: 'player_not_linked' };
  }

  const grants = await listDomainGrantsForUser(player.userId);
  const matched = grants.some((grant) => hostMatchesDomain(host, grant.domain, grant.includeSubdomains));

  if (!matched) {
    return {
      allowed: false,
      reason: 'domain_not_permitted',
      userId: player.userId
    };
  }

  return {
    allowed: true,
    reason: 'ok',
    userId: player.userId
  };
};
