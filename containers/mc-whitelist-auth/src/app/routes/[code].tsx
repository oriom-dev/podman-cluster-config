import { createRoute } from 'honox/factory';
import { auth, isGoogleAuthConfigured } from '../lib/auth';
import { decideScopesForChallenge, selectSignInProviderForHost } from '../lib/access-policy';
import {
  appendAuditLog,
  consumeMinecraftAccessChallengeForUser,
  findMinecraftAccessChallengeByCode,
  normalizeChallengeCode,
  upsertDomainGrantForUser,
  upsertMinecraftPlayerForUser
} from '../lib/db';
import styles from '../styles/home.module.css';

export default createRoute(async (c) => {
  const codeInput = c.req.param('code') ?? '';
  const code = normalizeChallengeCode(codeInput);

  if (!code) {
    return c.render(
      <section class={styles.panel}>
        <p class={styles.warning}>認証コードの形式が正しくありません。</p>
        <a class={styles.buttonSecondary} href='/'>
          トップへ戻る
        </a>
      </section>
    );
  }

  const challenge = await findMinecraftAccessChallengeByCode(code);
  if (!challenge) {
    return c.render(
      <section class={styles.panel}>
        <p class={styles.warning}>認証コードが見つかりませんでした。</p>
        <a class={styles.buttonSecondary} href='/'>
          トップへ戻る
        </a>
      </section>
    );
  }

  const now = new Date();
  if (challenge.expiresAt.getTime() <= now.getTime()) {
    return c.render(
      <section class={styles.panel}>
        <p class={styles.warning}>認証コードの有効期限が切れています。サーバーに再参加して新しい案内を受け取ってください。</p>
        <a class={styles.buttonSecondary} href='/'>
          トップへ戻る
        </a>
      </section>
    );
  }

  const provider = selectSignInProviderForHost(challenge.attemptedHost);
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  const user = session?.user;

  if (!user) {
    if (provider === 'google' && !isGoogleAuthConfigured) {
      return c.render(
        <section class={styles.panel}>
          <p class={styles.warning}>Googleログインの設定が未完了です。</p>
          <p class={styles.meta}>管理者へ連絡してください。</p>
        </section>
      );
    }

    return c.render(
      <section class={styles.panel}>
        <p class={styles.lead}>ログインして認証を完了してください。</p>

        <form class={styles.form} method='post' action='/auth/start'>
          <input type='hidden' name='next' value={`/${challenge.code}`} />
          <input type='hidden' name='provider' value={provider} />
          <button class={styles.button} type='submit'>
            Googleでログイン
          </button>
        </form>
      </section>
    );
  }

  const consumeResult = await consumeMinecraftAccessChallengeForUser(challenge.code, user.id);

  if (consumeResult.status === 'already_used') {
    const consumed = consumeResult.challenge;

    if (consumed?.consumedByUserId === user.id) {
      return c.render(
        <section class={styles.panel}>
          <p class={styles.success}>この認証はすでに完了しています。サーバーへ再参加してください。</p>
          <a class={styles.buttonSecondary} href='/'>
            トップへ戻る
          </a>
        </section>
      );
    }

    return c.render(
      <section class={styles.panel}>
        <p class={styles.warning}>この認証コードはすでに使用されています。</p>
        <p class={styles.meta}>サーバーに再参加して新しい案内を受け取ってください。</p>
      </section>
    );
  }

  if (consumeResult.status === 'expired') {
    return c.render(
      <section class={styles.panel}>
        <p class={styles.warning}>認証コードの有効期限が切れています。サーバーに再参加して新しい案内を受け取ってください。</p>
      </section>
    );
  }

  if (consumeResult.status !== 'consumed' || !consumeResult.challenge) {
    return c.render(
      <section class={styles.panel}>
        <p class={styles.warning}>この認証コードは現在使用できません。</p>
      </section>
    );
  }

  const consumed = consumeResult.challenge;

  try {
    const scopes = decideScopesForChallenge({
      attemptedHost: consumed.attemptedHost,
      userEmail: user.email,
      playerUuid: consumed.playerUuid,
      playerUsername: consumed.playerUsername,
      challengeCode: consumed.code
    });

    if (scopes.length === 0) {
      return c.render(
        <section class={styles.panel}>
          <p class={styles.warning}>アクセス範囲を確定できなかったため、認証を完了できませんでした。</p>
        </section>
      );
    }

    const linkedPlayer = await upsertMinecraftPlayerForUser(user.id, consumed.playerUuid, consumed.playerUsername);

    for (const scope of scopes) {
      await upsertDomainGrantForUser(user.id, scope.domain, scope.includeSubdomains);
    }

    await appendAuditLog({
      action: 'access_challenge_completed',
      actorUserId: user.id,
      actorEmail: user.email,
      targetUserId: user.id,
      targetEmail: user.email,
      metadata: {
        code: consumed.code,
        host: consumed.attemptedHost,
        playerUuid: linkedPlayer.uuid,
        playerUsername: linkedPlayer.username,
        scopes
      }
    });

    return c.render(
      <section class={styles.panel}>
        <p class={styles.success}>認証が完了しました。サーバーへ再参加してください。</p>
        <a class={styles.buttonSecondary} href='/'>
          トップへ戻る
        </a>
      </section>
    );
  } catch {
    return c.render(
      <section class={styles.panel}>
        <p class={styles.warning}>認証処理に失敗しました。時間をおいて再試行してください。</p>
      </section>
    );
  }
});
