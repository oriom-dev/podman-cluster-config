import { ColumnType, Kysely, PostgresDialect, sql } from 'kysely';
import { lookup } from 'node:dns/promises';
import { readFile } from 'node:fs/promises';
import { Pool } from 'pg';
import { env } from './env';

type TimestampColumn = ColumnType<Date, Date | string | undefined, Date | string | undefined>;
type NullableTimestampColumn = ColumnType<Date | null, Date | string | null | undefined, Date | string | null | undefined>;
type BooleanColumn = ColumnType<boolean, boolean | undefined, boolean | undefined>;
type NullableBooleanColumn = ColumnType<boolean | null, boolean | null | undefined, boolean | null | undefined>;
type NullableTextColumn = ColumnType<string | null, string | null | undefined, string | null | undefined>;

type UserRow = {
  id: string;
  name: string;
  email: string;
  emailVerified: BooleanColumn;
  image: NullableTextColumn;
  createdAt: TimestampColumn;
  updatedAt: TimestampColumn;
};

type SessionRow = {
  id: string;
  expiresAt: TimestampColumn;
  token: string;
  createdAt: TimestampColumn;
  updatedAt: TimestampColumn;
  ipAddress: NullableTextColumn;
  userAgent: NullableTextColumn;
  userId: string;
};

type AccountRow = {
  id: string;
  accountId: string;
  providerId: string;
  userId: string;
  accessToken: NullableTextColumn;
  refreshToken: NullableTextColumn;
  idToken: NullableTextColumn;
  accessTokenExpiresAt: NullableTimestampColumn;
  refreshTokenExpiresAt: NullableTimestampColumn;
  scope: NullableTextColumn;
  password: NullableTextColumn;
  createdAt: TimestampColumn;
  updatedAt: TimestampColumn;
};

type VerificationRow = {
  id: string;
  identifier: string;
  value: string;
  expiresAt: TimestampColumn;
  createdAt: TimestampColumn;
  updatedAt: TimestampColumn;
};

type MinecraftPlayerLinkRow = {
  uuid: string;
  username: string;
  userId: string;
  createdAt: TimestampColumn;
  updatedAt: TimestampColumn;
};

type MinecraftAccessChallengeRow = {
  code: string;
  playerUuid: string;
  playerUsername: string;
  attemptedHost: string;
  createdAt: TimestampColumn;
  expiresAt: TimestampColumn;
  consumedAt: NullableTimestampColumn;
  consumedByUserId: NullableTextColumn;
};

type UserDomainGrantRow = {
  userId: string;
  domain: string;
  includeSubdomains: BooleanColumn;
  createdAt: TimestampColumn;
  updatedAt: TimestampColumn;
};

type AuditLogRow = {
  id: string;
  action: string;
  actorUserId: NullableTextColumn;
  actorEmail: NullableTextColumn;
  targetUserId: NullableTextColumn;
  targetEmail: NullableTextColumn;
  metadata: string;
  createdAt: TimestampColumn;
};

interface Database {
  user: UserRow;
  session: SessionRow;
  account: AccountRow;
  verification: VerificationRow;
  minecraft_player_link: MinecraftPlayerLinkRow;
  minecraft_access_challenge: MinecraftAccessChallengeRow;
  user_domain_grant: UserDomainGrantRow;
  audit_log: AuditLogRow;
}

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

export const db = new Kysely<Database>({
  dialect: new PostgresDialect({ pool })
});

let schemaPromise: Promise<void> | null = null;

const bootstrapSchemaSql = `
CREATE TABLE IF NOT EXISTS "user" (
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "emailVerified" BOOL NOT NULL DEFAULT false,
  "image" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS user_email_unique ON "user" ("email");

CREATE TABLE IF NOT EXISTS "session" (
  "id" TEXT PRIMARY KEY,
  "expiresAt" TIMESTAMPTZ NOT NULL,
  "token" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "ipAddress" TEXT,
  "userAgent" TEXT,
  "userId" TEXT NOT NULL REFERENCES "user"("id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS session_token_unique ON "session" ("token");
CREATE INDEX IF NOT EXISTS session_user_id_idx ON "session" ("userId");

CREATE TABLE IF NOT EXISTS "account" (
  "id" TEXT PRIMARY KEY,
  "accountId" TEXT NOT NULL,
  "providerId" TEXT NOT NULL,
  "userId" TEXT NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
  "accessToken" TEXT,
  "refreshToken" TEXT,
  "idToken" TEXT,
  "accessTokenExpiresAt" TIMESTAMPTZ,
  "refreshTokenExpiresAt" TIMESTAMPTZ,
  "scope" TEXT,
  "password" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS account_provider_account_unique ON "account" ("providerId", "accountId");
CREATE INDEX IF NOT EXISTS account_user_id_idx ON "account" ("userId");

CREATE TABLE IF NOT EXISTS "verification" (
  "id" TEXT PRIMARY KEY,
  "identifier" TEXT NOT NULL,
  "value" TEXT NOT NULL,
  "expiresAt" TIMESTAMPTZ NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS verification_identifier_idx ON "verification" ("identifier");

CREATE TABLE IF NOT EXISTS "minecraft_player_link" (
  "uuid" TEXT PRIMARY KEY,
  "username" TEXT NOT NULL,
  "userId" TEXT NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS minecraft_player_link_user_id_idx ON "minecraft_player_link" ("userId");

CREATE TABLE IF NOT EXISTS "minecraft_access_challenge" (
  "code" TEXT PRIMARY KEY,
  "playerUuid" TEXT NOT NULL,
  "playerUsername" TEXT NOT NULL,
  "attemptedHost" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "expiresAt" TIMESTAMPTZ NOT NULL,
  "consumedAt" TIMESTAMPTZ,
  "consumedByUserId" TEXT REFERENCES "user"("id") ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS minecraft_access_challenge_expires_at_idx ON "minecraft_access_challenge" ("expiresAt");
CREATE INDEX IF NOT EXISTS minecraft_access_challenge_attempted_host_idx ON "minecraft_access_challenge" ("attemptedHost");
CREATE INDEX IF NOT EXISTS minecraft_access_challenge_player_uuid_idx ON "minecraft_access_challenge" ("playerUuid");

CREATE TABLE IF NOT EXISTS "user_domain_grant" (
  "userId" TEXT NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
  "domain" TEXT NOT NULL,
  "includeSubdomains" BOOL NOT NULL DEFAULT true,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT "user_domain_grant_pk" PRIMARY KEY ("userId", "domain")
);

CREATE INDEX IF NOT EXISTS user_domain_grant_user_id_idx ON "user_domain_grant" ("userId");

CREATE TABLE IF NOT EXISTS "audit_log" (
  "id" TEXT PRIMARY KEY,
  "action" TEXT NOT NULL,
  "actorUserId" TEXT,
  "actorEmail" TEXT,
  "targetUserId" TEXT,
  "targetEmail" TEXT,
  "metadata" TEXT NOT NULL DEFAULT '{}',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS audit_log_created_at_idx ON "audit_log" ("createdAt");
CREATE INDEX IF NOT EXISTS audit_log_action_idx ON "audit_log" ("action");
`;

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
      await client.query(bootstrapSchemaSql);
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
    .insertInto('minecraft_player_link')
    .values({
      uuid,
      username,
      userId,
      updatedAt: new Date()
    })
    .onConflict((oc) =>
      oc.column('uuid').doUpdateSet({
        userId,
        username,
        updatedAt: new Date()
      })
    )
    .execute();

  return { uuid, username };
};

export const listMinecraftPlayersForUser = async (userId: string): Promise<MinecraftPlayerLink[]> => {
  await ensureSchema();
  return db
    .selectFrom('minecraft_player_link')
    .select(['uuid', 'username', 'userId'])
    .where('userId', '=', userId)
    .orderBy('username', 'asc')
    .execute();
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
      .insertInto('minecraft_access_challenge')
      .values({
        code,
        playerUuid,
        playerUsername,
        attemptedHost,
        expiresAt,
        consumedAt: null,
        consumedByUserId: null
      })
      .onConflict((oc) => oc.doNothing())
      .returning([
        'code',
        'playerUuid',
        'playerUsername',
        'attemptedHost',
        'createdAt',
        'expiresAt',
        'consumedAt',
        'consumedByUserId'
      ])
      .executeTakeFirst();

    if (inserted) {
      return inserted;
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

  return (
    (await db
      .selectFrom('minecraft_access_challenge')
      .select([
        'code',
        'playerUuid',
        'playerUsername',
        'attemptedHost',
        'createdAt',
        'expiresAt',
        'consumedAt',
        'consumedByUserId'
      ])
      .where('code', '=', code)
      .limit(1)
      .executeTakeFirst()) ?? null
  );
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
    .updateTable('minecraft_access_challenge')
    .set({
      consumedAt: now,
      consumedByUserId: userId
    })
    .where('code', '=', code)
    .where('consumedAt', 'is', null)
    .where('expiresAt', '>', now)
    .returning([
      'code',
      'playerUuid',
      'playerUsername',
      'attemptedHost',
      'createdAt',
      'expiresAt',
      'consumedAt',
      'consumedByUserId'
    ])
    .executeTakeFirst();

  if (updated) {
    return { status: 'consumed', challenge: updated };
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
    .selectFrom('minecraft_player_link')
    .innerJoin('user', 'minecraft_player_link.userId', 'user.id')
    .select((eb) => [
      eb.ref('minecraft_player_link.uuid').as('uuid'),
      eb.ref('minecraft_player_link.username').as('username'),
      eb.ref('minecraft_player_link.userId').as('userId'),
      eb.ref('user.email').as('email')
    ])
    .orderBy('user.email', 'asc')
    .orderBy('minecraft_player_link.username', 'asc')
    .execute();
};

export const listUsers = async (): Promise<Array<{ id: string; email: string; name: string }>> => {
  await ensureSchema();
  const rows = await db.selectFrom('user').select(['id', 'email', 'name']).orderBy('email', 'asc').execute();
  return rows;
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

  const rows = await db
    .selectFrom('user')
    .select(['id', 'email', 'name'])
    .where(sql<boolean>`lower(${sql.ref('email')}) like ${pattern} or lower(${sql.ref('name')}) like ${pattern}`)
    .orderBy('email', 'asc')
    .limit(Math.max(1, Math.min(limit, 100)))
    .execute();

  return rows;
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

  await db.insertInto('audit_log').values({
    id: createAuditLogId(),
    action,
    actorUserId: entry.actorUserId ?? null,
    actorEmail: entry.actorEmail ?? null,
    targetUserId: entry.targetUserId ?? null,
    targetEmail: entry.targetEmail ?? null,
    metadata: JSON.stringify(entry.metadata ?? {}),
    createdAt: new Date()
  }).execute();
};

export const listAuditLogs = async (queryInput: string, limit = 150): Promise<AuditLogRecord[]> => {
  await ensureSchema();

  const query = queryInput.trim().toLowerCase();
  const cappedLimit = Math.max(1, Math.min(limit, 400));

  if (!query) {
    return db
      .selectFrom('audit_log')
      .select(['id', 'action', 'actorUserId', 'actorEmail', 'targetUserId', 'targetEmail', 'metadata', 'createdAt'])
      .orderBy('createdAt', 'desc')
      .limit(cappedLimit)
      .execute();
  }

  const pattern = `%${query}%`;

  return db
    .selectFrom('audit_log')
    .select(['id', 'action', 'actorUserId', 'actorEmail', 'targetUserId', 'targetEmail', 'metadata', 'createdAt'])
    .where(
      sql<boolean>`lower(${sql.ref('action')}) like ${pattern} or lower(coalesce(${sql.ref('actorEmail')}, '')) like ${pattern} or lower(coalesce(${sql.ref('targetEmail')}, '')) like ${pattern} or lower(${sql.ref('metadata')}) like ${pattern}`
    )
    .orderBy('createdAt', 'desc')
    .limit(cappedLimit)
    .execute();
};

export const findUserByEmail = async (emailInput: string): Promise<{ id: string; email: string; name: string } | null> => {
  await ensureSchema();

  const email = emailInput.trim().toLowerCase();
  if (!email) {
    return null;
  }

  return (await db.selectFrom('user').select(['id', 'email', 'name']).where('email', '=', email).limit(1).executeTakeFirst()) ?? null;
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
    .insertInto('user_domain_grant')
    .values({
      userId,
      domain,
      includeSubdomains,
      updatedAt: new Date()
    })
    .onConflict((oc) =>
      oc.columns(['userId', 'domain']).doUpdateSet({
        includeSubdomains,
        updatedAt: new Date()
      })
    )
    .execute();

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

  await db.deleteFrom('user_domain_grant').where('userId', '=', userId).where('domain', '=', domain).execute();
};

export const listDomainGrantsForUser = async (userId: string): Promise<DomainGrant[]> => {
  await ensureSchema();

  return db
    .selectFrom('user_domain_grant')
    .select(['userId', 'domain', 'includeSubdomains'])
    .where('userId', '=', userId)
    .orderBy('domain', 'asc')
    .execute();
};

export const listAllDomainGrantsWithUsers = async (): Promise<
  Array<{ userId: string; email: string; domain: string; includeSubdomains: boolean }>
> => {
  await ensureSchema();

  return db
    .selectFrom('user_domain_grant')
    .innerJoin('user', 'user_domain_grant.userId', 'user.id')
    .select((eb) => [
      eb.ref('user_domain_grant.userId').as('userId'),
      eb.ref('user.email').as('email'),
      eb.ref('user_domain_grant.domain').as('domain'),
      eb.ref('user_domain_grant.includeSubdomains').as('includeSubdomains')
    ])
    .orderBy('user.email', 'asc')
    .orderBy('user_domain_grant.domain', 'asc')
    .execute();
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

  const player = await db
    .selectFrom('minecraft_player_link')
    .select(['userId'])
    .where('uuid', '=', uuid)
    .limit(1)
    .executeTakeFirst();

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
