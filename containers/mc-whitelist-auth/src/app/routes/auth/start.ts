import { createRoute } from 'honox/factory';
import { auth, isGoogleAuthConfigured } from '../../lib/auth';

export default createRoute(async (c) => {
  if (c.req.method !== 'POST') {
    return c.text('Method Not Allowed', 405);
  }

  const form = await c.req.formData();
  const provider = `${form.get('provider') ?? 'google'}`.trim().toLowerCase();
  const rawNext = `${form.get('next') ?? ''}`.trim();
  const callbackURL = rawNext.startsWith('/') && !rawNext.startsWith('//') ? rawNext : '/';

  if (provider !== 'google') {
    return c.redirect(`/?error=${encodeURIComponent('対応していないログイン方式です。')}`);
  }

  if (!isGoogleAuthConfigured) {
    return c.text('Googleログインの設定が未完了です。', 500);
  }

  return auth.api.signInSocial({
    body: {
      provider: 'google',
      callbackURL,
      errorCallbackURL: `/?error=${encodeURIComponent('Googleログインに失敗しました。')}`
    },
    headers: c.req.raw.headers,
    asResponse: true
  });
});
