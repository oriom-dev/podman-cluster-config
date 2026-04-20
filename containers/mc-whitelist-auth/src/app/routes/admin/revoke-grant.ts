import { createRoute } from 'honox/factory';
import { auth } from '../../lib/auth';
import { appendAuditLog, findUserByEmail, isAdminEmail, revokeDomainGrantForUser } from '../../lib/db';

export const POST = createRoute(async (c) => {
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  const user = session?.user;
  if (!user || !isAdminEmail(user.email)) {
    return c.redirect(`/?error=${encodeURIComponent('管理者権限が必要です。')}`);
  }

  const form = await c.req.formData();
  const email = `${form.get('email') ?? ''}`;
  const domain = `${form.get('domain') ?? ''}`;

  try {
    const targetUser = await findUserByEmail(email);
    if (!targetUser) {
      return c.redirect(`/admin?error=${encodeURIComponent('指定されたEmailは登録されていません。')}`);
    }

    await revokeDomainGrantForUser(targetUser.id, domain);
    await appendAuditLog({
      action: 'domain_grant_revoke',
      actorUserId: user.id,
      actorEmail: user.email,
      targetUserId: targetUser.id,
      targetEmail: targetUser.email,
      metadata: {
        domain
      }
    });

    return c.redirect(`/admin?notice=${encodeURIComponent(`ドメイン許可を取り消しました: ${domain} / ${email}`)}`);
  } catch {
    return c.redirect(`/admin?error=${encodeURIComponent('ドメイン許可の取り消しに失敗しました。')}`);
  }
});
