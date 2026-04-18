import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { bearerAuth } from 'hono/bearer-auth';
import z from 'zod';

const app = new Hono();

// 環境変数からシークレットを読み込み
const env = z.object({
  PROXY_AUTH_TOKEN: z.string().min(1, 'PROXY_AUTH_TOKEN is required'),
  JPOST_API_HOST: z.string().min(1, 'JPOST_API_HOST is required'),
  JPOST_CLIENT_ID: z.string().min(1, 'JPOST_CLIENT_ID is required'),
  JPOST_CLIENT_SECRET: z.string().min(1, 'JPOST_CLIENT_SECRET is required'),
}).parse(process.env);

const SEARCH_CODE_PATTERN = /^[0-9A-Za-z]{7}$/;
const FETCH_TIMEOUT_MS = 10000;

// ミドルウェア: アクセスをトークンで認証
app.use('/api/*', bearerAuth({ token: env.PROXY_AUTH_TOKEN }));

app.get('/api/v2/searchcode/:code', async (c) => {
  const rawCode = c.req.param('code').trim();

  // 郵便番号・デジタルアドレス向けに7文字の英数字を許可
  if (!SEARCH_CODE_PATTERN.test(rawCode)) {
    return c.json({ message: 'Invalid code format. Expected 7 alphanumeric characters.' }, 400);
  }

  const code = rawCode.toUpperCase();

  try {
    const tokenResponse = await fetch(`https://${env.JPOST_API_HOST}/api/v2/j/token`, {
      method: 'POST',
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        grant_type: 'client_credentials',
        client_id: env.JPOST_CLIENT_ID,
        secret_key: env.JPOST_CLIENT_SECRET
      })
    });

    if (!tokenResponse.ok) {
      console.error('Japan Post API token request failed', { status: tokenResponse.status });
      return c.json({ message: 'Failed to obtain token from official API' }, 502);
    }

    const tokenData = z.object({
      token: z.string().min(1, 'Access token is required')
    }).safeParse(await tokenResponse.json());

    if (!tokenData.success) {
      console.error(`Japan Post API token response is invalid: ${JSON.stringify(tokenData.error.issues)}`);
      return c.json({ message: 'Invalid token response from official API' }, 502);
    }

    const accessToken = tokenData.data.token;
    const query = new URLSearchParams(c.req.query()).toString();
    const endpoint = `https://${env.JPOST_API_HOST}/api/v2/searchcode/${encodeURIComponent(code)}${query ? `?${query}` : ''}`;

    // 日本郵便APIへのリクエスト
    const response = await fetch(endpoint, {
      method: 'GET',
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Accept': 'application/json'
      }
    });

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
