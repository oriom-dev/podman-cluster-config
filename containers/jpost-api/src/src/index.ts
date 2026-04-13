import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { bearerAuth } from 'hono/bearer-auth';

const app = new Hono();

type JPostTokenResponse = {
  access_token: string;
};

function getRequiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function isJPostTokenResponse(value: unknown): value is JPostTokenResponse {
  if (typeof value !== 'object' || value === null) {
    return false;
  }

  const maybeToken = value as { access_token?: unknown };
  return typeof maybeToken.access_token === 'string' && maybeToken.access_token.length > 0;
}

// 環境変数からシークレットを読み込み
const PROXY_AUTH_TOKEN = getRequiredEnv('PROXY_AUTH_TOKEN');
const JPOST_CLIENT_ID = getRequiredEnv('JPOST_CLIENT_ID');
const JPOST_CLIENT_SECRET = getRequiredEnv('JPOST_CLIENT_SECRET');

const JPOST_API_URL = 'https://api.da.pf.japanpost.jp';
const SEARCH_CODE_PATTERN = /^[0-9A-Za-z]{7}$/;
const FETCH_TIMEOUT_MS = 10000;

// ミドルウェア: アクセスをトークンで認証
// これにより、Authorization: Bearer <PROXY_AUTH_TOKEN> ヘッダーがないリクエストを401で弾きます
app.use('/api/*', bearerAuth({ token: PROXY_AUTH_TOKEN }));

app.get('/api/v2/searchcode/:code', async (c) => {
  const rawCode = c.req.param('code').trim();

  // 郵便番号・デジタルアドレス向けに7文字の英数字を許可
  if (!SEARCH_CODE_PATTERN.test(rawCode)) {
    return c.json({ error: 'Invalid code format. Expected 7 alphanumeric characters.' }, 400);
  }

  const code = rawCode.toUpperCase();

  try {
    const tokenResponse = await fetch(`${JPOST_API_URL}/api/v2/j/token`, {
      method: 'POST',
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        grant_type: 'client_credentials',
        client_id: JPOST_CLIENT_ID,
        secret_key: JPOST_CLIENT_SECRET
      })
    });

    if (!tokenResponse.ok) {
      console.error('Japan Post API token request failed', { status: tokenResponse.status });
      return c.json({ error: 'Failed to obtain token from official API' }, 502);
    }

    const tokenData: unknown = await tokenResponse.json();
    if (!isJPostTokenResponse(tokenData)) {
      console.error('Japan Post API token response is invalid');
      return c.json({ error: 'Invalid token response from official API' }, 502);
    }

    const accessToken = tokenData.access_token;
    const query = new URLSearchParams(c.req.query()).toString();
    const endpoint = `${JPOST_API_URL}/api/v2/searchcode/${encodeURIComponent(code)}${query ? `?${query}` : ''}`;

    // 日本郵便APIへのリクエスト
    const response = await fetch(endpoint, {
      method: 'GET',
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Accept': 'application/json'
      }
    });

    if (!response.ok) {
      console.error('Japan Post API search request failed', { status: response.status });
      return c.json({ error: 'Failed to fetch data from official API' }, 502);
    }

    // 取得した住所データをそのまま返却
    const data = await response.json();
    return c.json(data);

  } catch (error) {
    console.error('Fetch error:', error instanceof Error ? error.message : String(error));
    return c.json({ error: 'Internal Server Error' }, 500);
  }
});

// 内部での死活監視用ヘルスチェック (認証不要)
app.get('/health', (c) => c.text('OK'));

const port = 8080;
console.log(`JPost Proxy Server is running on port ${port}`);

serve({
  fetch: app.fetch,
  port
});
