import { createRoute } from 'honox/factory';
import { auth } from '../../lib/auth';
import {
  isAdminEmail,
  listAllDomainGrantsWithUsers,
  listAllMinecraftPlayersWithUsers,
  listAuditLogs,
  listUsers,
  searchUsers
} from '../../lib/db';
import styles from '../../styles/home.module.css';

export default createRoute(async (c) => {
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  const user = session?.user;

  if (!user || !isAdminEmail(user.email)) {
    return c.redirect(`/?error=${encodeURIComponent('管理者権限が必要です。')}`);
  }

  const query = (c.req.query('q') ?? '').trim();
  const queryLower = query.toLowerCase();

  const users = query ? await searchUsers(query, 100) : await listUsers();
  const userIdFilter = query ? new Set(users.map((entry) => entry.id)) : null;

  const allGrants = await listAllDomainGrantsWithUsers();
  const allPlayers = await listAllMinecraftPlayersWithUsers();
  const grants = userIdFilter
    ? allGrants.filter((grant) => userIdFilter.has(grant.userId) || grant.domain.toLowerCase().includes(queryLower))
    : allGrants;
  const players = userIdFilter
    ? allPlayers.filter(
        (player) =>
          userIdFilter.has(player.userId) ||
          player.username.toLowerCase().includes(queryLower) ||
          player.uuid.toLowerCase().includes(queryLower)
      )
    : allPlayers;
  const auditLogs = await listAuditLogs(query, 200);
  const notice = c.req.query('notice');
  const error = c.req.query('error');

  return c.render(
    <section class={styles.panel}>
      <p class={styles.lead}>管理ポリシーパネル</p>
      <p class={styles.meta}>管理者としてログイン中: {user.email}</p>
      {notice ? <p class={styles.success}>{notice}</p> : null}
      {error ? <p class={styles.warning}>{error}</p> : null}

      <form class={styles.form} method='get' action='/admin'>
        <label class={styles.label}>
          ユーザー・ドメイン・UUID・ログを検索
          <input class={styles.input} type='text' name='q' value={query} placeholder='email, username, domain, uuid' />
        </label>
        <div class={styles.row}>
          <button class={styles.button} type='submit'>
            検索
          </button>
          {query ? (
            <a class={styles.buttonSecondary} href='/admin'>
              検索条件をクリア
            </a>
          ) : null}
        </div>
      </form>

      <div class={styles.section}>
        <h2 class={styles.sectionTitle}>一致したユーザー ({users.length})</h2>
        {users.length === 0 ? (
          <p class={styles.meta}>一致するユーザーは見つかりませんでした。</p>
        ) : (
          <div class={styles.tableWrap}>
            <table class={styles.table}>
              <thead>
                <tr>
                  <th>Email</th>
                  <th>名前</th>
                  <th>ユーザーID</th>
                </tr>
              </thead>
              <tbody>
                {users.map((entry) => (
                  <tr key={entry.id}>
                    <td>{entry.email}</td>
                    <td>{entry.name}</td>
                    <td>{entry.id}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <form class={styles.form} method='post' action='/admin/grants'>
        <label class={styles.label}>
          対象ユーザーのEmail
          <input class={styles.input} type='email' name='email' list='known-users' required />
          <datalist id='known-users'>
            {users.map((entry) => (
              <option key={entry.id} value={entry.email} />
            ))}
          </datalist>
        </label>

        <label class={styles.label}>
          許可するドメイン
          <input class={styles.input} type='text' name='domain' placeholder='mc.oriom.dev' required />
        </label>

        <label class={styles.checkboxLabel}>
          <input type='checkbox' name='includeSubdomains' value='1' defaultChecked />
          サブドメインを含める
        </label>

        <button class={styles.button} type='submit'>
          ドメイン許可を保存
        </button>
      </form>

      <div class={styles.section}>
        <h2 class={styles.sectionTitle}>現在のドメイン許可</h2>
        {grants.length === 0 ? (
          <p class={styles.meta}>許可設定はありません。</p>
        ) : (
          <div class={styles.tableWrap}>
            <table class={styles.table}>
              <thead>
                <tr>
                  <th>Email</th>
                  <th>ドメイン</th>
                  <th>ルール</th>
                  <th>操作</th>
                </tr>
              </thead>
              <tbody>
                {grants.map((grant) => (
                  <tr key={`${grant.userId}:${grant.domain}`}>
                    <td>{grant.email}</td>
                    <td>{grant.domain}</td>
                    <td>{grant.includeSubdomains ? 'サブドメイン含む' : '完全一致のみ'}</td>
                    <td>
                      <form method='post' action='/admin/revoke-grant'>
                        <input type='hidden' name='email' value={grant.email} />
                        <input type='hidden' name='domain' value={grant.domain} />
                        <button class={styles.linkButton} type='submit'>
                          取り消し
                        </button>
                      </form>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div class={styles.section}>
        <h2 class={styles.sectionTitle}>登録済みMinecraftプロフィール</h2>
        {players.length === 0 ? (
          <p class={styles.meta}>連携済みプロフィールはありません。</p>
        ) : (
          <div class={styles.tableWrap}>
            <table class={styles.table}>
              <thead>
                <tr>
                  <th>Email</th>
                  <th>ユーザー名</th>
                  <th>UUID</th>
                </tr>
              </thead>
              <tbody>
                {players.map((player) => (
                  <tr key={player.uuid}>
                    <td>{player.email}</td>
                    <td>{player.username}</td>
                    <td>{player.uuid}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div class={styles.section}>
        <h2 class={styles.sectionTitle}>監査ログ</h2>
        {auditLogs.length === 0 ? (
          <p class={styles.meta}>この条件に一致する監査ログはありません。</p>
        ) : (
          <div class={styles.tableWrap}>
            <table class={styles.table}>
              <thead>
                <tr>
                  <th>日時</th>
                  <th>操作</th>
                  <th>実行者</th>
                  <th>対象</th>
                  <th>詳細</th>
                </tr>
              </thead>
              <tbody>
                {auditLogs.map((log) => (
                  <tr key={log.id}>
                    <td>{new Date(log.createdAt).toISOString()}</td>
                    <td>{log.action}</td>
                    <td>{log.actorEmail ?? '-'}</td>
                    <td>{log.targetEmail ?? '-'}</td>
                    <td class={styles.code}>{log.metadata}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <a class={styles.buttonSecondary} href='/'>
        トップへ戻る
      </a>
    </section>
  );
});
