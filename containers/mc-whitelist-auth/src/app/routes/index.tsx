import { createRoute } from 'honox/factory';
import { auth } from '../lib/auth';
import { isAdminEmail } from '../lib/db';
import styles from '../styles/home.module.css';

export default createRoute(async (c) => {
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  const user = session?.user ?? null;
  const isAdmin = isAdminEmail(user?.email);
  const requestedNext = `${c.req.query('next') ?? ''}`.trim();
  const nextPath = requestedNext.startsWith('/') && !requestedNext.startsWith('//') ? requestedNext : '/';

  const notice = c.req.query('notice');
  const error = c.req.query('error');

  return c.render(
    <section class={styles.panel}>
      <h2 class={styles.title}>Minecraftアカウント認証</h2>
      <p class={styles.lead}>サーバー参加時に表示される案内リンクから認証を完了してください。</p>
      {notice ? <p class={styles.success}>{notice}</p> : null}
      {error ? <p class={styles.warning}>{error}</p> : null}

      {!user ? (
        <div class={styles.signInCard}>
          <form method='post' action='/auth/start' class={styles.form}>
            <input type='hidden' name='provider' value='google' />
            <input type='hidden' name='next' value={nextPath} />
            <button class={styles.googleButton} type='submit'>
              <span class={styles.googleLogo} aria-hidden='true'>
                <svg viewBox='0 0 48 48' width='20' height='20'>
                  <path
                    fill='#FFC107'
                    d='M43.611 20.083H42V20H24v8h11.303C33.654 32.657 29.207 36 24 36c-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.846 1.154 7.959 3.041l5.657-5.657C34.059 6.053 29.27 4 24 4 12.954 4 4 12.954 4 24s8.954 20 20 20 20-8.954 20-20c0-1.341-.138-2.651-.389-3.917z'
                  />
                  <path
                    fill='#FF3D00'
                    d='M6.306 14.691l6.571 4.819C14.655 16.108 19.008 13 24 13c3.059 0 5.846 1.154 7.959 3.041l5.657-5.657C34.059 7.053 29.27 5 24 5 16.318 5 9.656 9.337 6.306 14.691z'
                  />
                  <path
                    fill='#4CAF50'
                    d='M24 44c5.171 0 9.86-1.977 13.409-5.196l-6.191-5.238C29.161 35.091 26.715 36 24 36c-5.186 0-9.623-3.329-11.283-7.946l-6.522 5.025C9.515 38.556 16.227 44 24 44z'
                  />
                  <path
                    fill='#1976D2'
                    d='M43.611 20.083H42V20H24v8h11.303a12.046 12.046 0 0 1-4.085 5.566l.003-.002 6.191 5.238C36.968 39.208 44 34 44 24c0-1.341-.138-2.651-.389-3.917z'
                  />
                </svg>
              </span>
              <span class={styles.googleButtonText}>
                <strong>Googleでログイン</strong>
                <small>認証を続ける</small>
              </span>
            </button>
          </form>
        </div>
      ) : (
        <>
          <p class={styles.meta}>{user.email} でログイン中です。</p>
          <p class={styles.meta}>サーバーで表示された案内リンクを開くと認証できます。</p>

          <div class={styles.row}>
            {isAdmin ? (
              <a class={styles.buttonSecondary} href='/admin'>
                管理ポリシーパネル
              </a>
            ) : null}
            <form method='post' action='/auth/sign-out'>
              <button class={styles.buttonSecondary} type='submit'>
                ログアウト
              </button>
            </form>
          </div>
        </>
      )}
    </section>
  );
});
