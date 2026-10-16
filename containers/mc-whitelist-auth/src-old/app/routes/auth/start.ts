import { createRoute } from 'honox/factory';

export const POST = createRoute(async (c) => {
  const form = await c.req.formData();
  const provider = `${form.get('provider') ?? 'google'}`.trim().toLowerCase();
  const rawNext = `${form.get('next') ?? ''}`.trim();
  const callbackURL = rawNext.startsWith('/') && !rawNext.startsWith('//') ? rawNext : '/';

  if (provider !== 'google') {
    return c.redirect(`/?error=${encodeURIComponent('対応していないログイン方式です。')}`);
  }

  const forwardedHeaders = new Headers({
    'content-type': 'application/json'
  });

  const cookie = c.req.raw.headers.get('cookie');
  if (cookie) {
    forwardedHeaders.set('cookie', cookie);
  }

  return fetch(new URL('/api/auth/sign-in/social', c.req.url), {
    method: 'POST',
    headers: forwardedHeaders,
    body: JSON.stringify({
      provider: 'google',
      callbackURL,
      errorCallbackURL: `/?error=${encodeURIComponent('Googleログインに失敗しました。')}`
    }),
    redirect: 'manual'
  });
});
