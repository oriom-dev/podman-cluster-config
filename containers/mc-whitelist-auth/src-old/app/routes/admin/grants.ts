import { createRoute } from 'honox/factory';
import { auth } from '../../lib/auth';
import { appendAuditLog, findUserByEmail, isAdminEmail, upsertDomainGrantForUser } from '../../lib/db';

export const POST = createRoute(async (c) => {
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  const user = session?.user;
  if (!user || !isAdminEmail(user.email)) {
    return c.redirect(`/?error=${encodeURIComponent('管理者権限が必要です。')}`);
  }

  const form = await c.req.formData();
  const email = `${form.get('email') ?? ''}`;
  const domain = `${form.get('domain') ?? ''}`;
  const includeSubdomains = form.get('includeSubdomains') === '1';

  try {
    const targetUser = await findUserByEmail(email);
    if (!targetUser) {
      return c.redirect(`/admin?error=${encodeURIComponent('指定されたEmailは登録されていません。')}`);
    }

    const saved = await upsertDomainGrantForUser(targetUser.id, domain, includeSubdomains);
    await appendAuditLog({
      action: 'domain_grant_upsert',
      actorUserId: user.id,
      actorEmail: user.email,
      targetUserId: targetUser.id,
      targetEmail: targetUser.email,
      metadata: {
        domain: saved.domain,
        includeSubdomains: saved.includeSubdomains
      }
    });

    return c.redirect(`/admin?notice=${encodeURIComponent(`ドメイン許可を保存しました: ${saved.domain} / ${targetUser.email}`)}`);
  } catch {
    return c.redirect(`/admin?error=${encodeURIComponent('ドメイン許可の保存に失敗しました。')}`);
  }
});
