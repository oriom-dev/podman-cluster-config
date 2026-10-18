# Mosimo importer production deployment — 2026-10-19 JST

Deployment/verification took place on 2026-10-18 around 19:44–19:56 UTC (2026-10-19 04:44–04:56 JST). This is an actual production result, superseding the local-only deployment gates in `sd_2607/appview/bsaf/DEPLOYMENT-CHECKLIST.md` for the server work described here. Device provisioning and receiver ingress/clock authorization remain separate.

## Published revisions and boundaries

- `jphacks/sd_2607`: **`78c84cfec4d0cbd62ecb0d542854ee996a0f7170`**, parent `e64201e`. A detached `commit-tree` used the latest `origin/main` as its base and copied only `pds/` and `appview/bsaf/` from the local server implementation. The complete changed-path list was checked before a normal fast-forward push. Local `main`/working tree were not switched or pushed; no client changes were published. Remote `apps/web/default.nix` already existed and needed no changes.
- `oriom-dev/podman-cluster-config`: **`90ba3f0`** configured the publisher/snapshot route and retained the existing prepared Caddy, host, migration-doc and public-config work; **`8dc4529`** committed the VPS-generated normal `nix flake update mosimo` lockfile.
- `mosimo` is pinned to the full server-only revision above, with `sha256-1pt48afKoOdDQwpuF3Tm5ktDpj/m2S071LagfFJlehM=`. `happyview` and unrelated inputs were not updated. No final path overrides.
- VPS checkout: `/home/operator/podman-cluster-config`, cloned from GitHub and pulled normally. At activation it was clean and at `8dc4529`.
- Activated system: `/nix/store/q1dslrzsbi7bm5qwaqxq2fjs8g15m9qr-nixos-system-kagoya-vps-26.05.20260409.4c1018d`.

## Access, backup and activation

Use `ssh -o StrictHostKeyChecking=yes -i C:/Users/chiba/.ssh/kagoya_nixos operator@133.18.180.180` from Windows. This shell's `~` resolves to `C:/Users/chiba/.config`, so a bare `~/.ssh/kagoya_nixos` failed; no host-key verification was disabled. `kagoya_default_podman` documents the old Ubuntu installation, not the current operator account. The VPS reported `NTPSynchronized=yes`.

Root-only backup directory: **`/var/backups/mosimo-deploy-20261018T1944/`** (0700), containing:

- `pds.sqlite` and `happyview.sqlite`, produced with Node's SQLite online backup API; both subsequently passed `PRAGMA quick_check`.
- Prior `/etc/nixos`, worker credentials/public roots, snapshot directory, and the previous `/run/current-system` target in `system-path`.

The initial bounded SSH backup command timed out after completing the PDS backup; inspection confirmed the remote HappyView backup was still running, not complete. The 3.5 GB HappyView database's continuous writes prevented completion, so `mosimo-bsaf` and `podman-happyview` were briefly stopped. Backup then completed; integrity checks passed before activation. No partial backup was treated as valid. Services resumed through the new NixOS activation.

Commands used after the normal input update:

```sh
nix build /home/operator/podman-cluster-config#nixosConfigurations.kagoya-vps.config.system.build.toplevel \
  --out-link /home/operator/mosimo-production-result --max-jobs 1 --cores 2
sudo nixos-rebuild switch --flake /home/operator/podman-cluster-config#kagoya-vps --max-jobs 1 --cores 2
```

Both completed successfully. Rollback must preserve live database/firehose sequence and complete trust high-water/CRL state: **do not restore old SQLite or snapshot state under the same public endpoint**. A system configuration rollback is not permission to rewind data.

## Importer identity and credential boundary

- Root fingerprint: `9d60fc70a23705b9c350caba47acf117374046442950da94979bbe500855676a`.
- Importer: **`did:plc:veuy37bwfkvnwx43itotn4ge`**; PDS `https://pds.oriom.dev`; WebSocket **`wss://pds.oriom.dev/`** (not `/nostr`).
- Organization remains **Mosimo BSAF importer (not JMA)**. No institutional/JMA authority is asserted.
- PLC `/log` and current document both returned 404 immediately before registration. Only then was the exact saved signed `private/importer-request.json` genesis POSTed unchanged to `plc.directory`; response 200. Afterwards `/log` contained one operation, canonical genesis bytes matched the saved request, and the current atproto key and PDS endpoint matched. An initial plain JSON-string equality check differed on property ordering; canonical CBOR equality passed.
- Certificate validity remains `2026-10-18T18:13:49Z` through `2026-11-17T18:13:49Z`; certId `b3f52501f4465ffc0590b514d8c1353b7393616ba04dc8a5b85ef30eeded1984`.
- Only worker `credentials.json` and public `roots.json` were transferred over verified SSH/SCP to `/var/lib/mosimo-importer/`, directory 0700/files 0600 root-owned. Remote key-shape validation confirmed only `chain,importer` and `atprotoSecret,binding,did,nostrSecret`; systemd `LoadCredential` supplies the worker secret.
- Root private key, PLC rotation secret and their backups remain in the local ignored, user-only-ACL issuer directory. No private key was put in Git, Nix source/store, the public web directory, firmware or this report.

## Snapshot publication and local scheduled issuer

Public URL: **https://pds.oriom.dev/.well-known/mosimo/trust/snapshot.cbor**. External HTTP verification returned 200, `Content-Type: application/cbor`, `Cache-Control: no-store`, 365-byte canonical CBOR, no redirects; the signature and current freshness were verified locally.

At deployment the expired sequence 3 snapshot and old receiver exports were archived in `private/before-production-sequence-3/` before refreshing and exporting:

- Initial receiver exports/public PDS config pin **minimum sequence 4** and the exact 5 JMA + 23 Kikikuru pairs. Ongoing refresh does **not** require changing that minimum or reprovisioning devices on every snapshot.
- Snapshot advanced **3 → 4 → 5 → 6**, keeping the complete prior CRL (zero revoked cert IDs/pubkeys). Sequence 5 came from an actual scheduled-task test, exit result **0**.
- Latest independently fetched/verified snapshot in this report: **sequence 6**, issued **`2026-10-18T19:53:20Z`**, valid until **`2026-10-18T20:53:20Z`**. This is a recorded absolute window, not a perpetual freshness claim.
- The hardened refresh script archives preceding signed state/CBOR under `private/snapshot-history/sequence-N/` before issuing later snapshots. Sequence 5 was archived before sequence 6. Initial sequence 4 was superseded before this automatic archival was added; do not claim an archive of every intermediate signed blob. Current cumulative high-water/CRL state was never reset.

Secret-free script: [`../scripts/refresh-mosimo-snapshot.py`](../scripts/refresh-mosimo-snapshot.py). It audits the existing user-only Windows ACLs, invokes the existing local identity CLI, verifies current signed/canonical snapshot bytes, uploads **only `snapshot.cbor`**, verifies the remote digest, and atomically replaces the root-owned, root:caddy 0640 public file. Temporary upload directory is operator-only 0700. A failed operation exits nonzero; it never renews an old signature or resets sequence/revocations. Re-run normally after a failed transfer to issue a higher sequence, or use `--publish-current` only while the signed snapshot remains fresh.

```sh
python scripts/refresh-mosimo-snapshot.py \
  --issuer C:/Users/chiba/Documents/src/jphacks/worktrees/sd_2607/protocol/sd_2607/appview/bsaf \
  --key C:/Users/chiba/.ssh/kagoya_nixos
```

Windows task **`\MosimoTrustSnapshot`** was installed using Task Scheduler XML (the long action exceeds `schtasks /TR`'s 261-character limit). Its definition is retained in ignored `private/snapshot-task.xml`. It runs every **30 minutes**, as the verified current user, **interactive-token/least privilege**, without saving a login password; overlapping task instances are ignored and runtime is limited to five minutes. The tested task finished with result 0, issued sequence 5 and successfully published it. The updated archival script was also run directly and published sequence 6. Task was enabled, next run 2026-10-19 05:19:35 JST when inspected.

**Availability limit:** the issuer must remain awake and that user logged on, with repository paths, ACL-audit script, Node/Python, SSH key and network available. Logoff/sleep or a transfer failure can cause snapshot expiry; receivers must fail closed. Keep these secured paths stable while the task is enabled. Monitor Task Scheduler result plus public signed `validUntil`; the online VPS deliberately has no root signing key. Disable with `schtasks /Change /TN MosimoTrustSnapshot /Disable` before moving/deleting the issuer. Renew/review the leaf before its November 17 expiry; snapshot refresh does not renew it.

## Live results and device-worker handoff

Final service check: **PDS, collector, publisher, HappyView and Caddy all active**, zero failed systemd units. Public PDS `/health` returned `{"ok":true}`; AppView `dev.oriom.mosimo.getFeed` and `https://mosimo.oriom.dev/` both returned HTTP 200. No subsequent publisher-held errors appeared during the inspected post-start window.

- Before deployment collector cursor: **1792351218201663**, retained in backup.
- After activation cursor: **1792352938674581**; no reset/backfill/fabricated source timestamps.
- Publisher observation: **22 accepted, 44 held, zero pending**. Old/unsupported originals are held without signing. JMA count 45 (latest original 19:20:16Z), Kikikuru count 21 (latest original 19:48:58Z). Collector naturally replayed its preserved cursor; manual backfill was unnecessary.
- No expired pending repository-base stall was encountered, and no commit/base was skipped or rewritten. If such a pending base later expires, the publisher deliberately holds; do not delete it or fabricate a replacement chain to unblock delivery.

The following real EVENTs were retrieved externally from `wss://pds.oriom.dev/`, and the corresponding importer records fetched via PDS `com.atproto.repo.getRecord`. Original records were separately fetched from their PLC-designated PDS `https://stropharia.us-west.host.bsky.network`; original URI/CID and canonical Lex-CBOR hash matched. This is current PDS/Jetstream provenance and CID consistency, **not verification of an original Bot's repository signature/inclusion or a claim of JMA authorization**.

### Preferred fresh weather event for ESP testing

- EVENT ID: **`30f6ed3bc1d3778e28218ec9de6d6f55b955a83ffdd0fce9c83b2ef458a1de0d`**.
- Importer PDS path: **`dev.oriom.mosimo.post/3my6exs5ek222`**.
- Importer record CID: `bafyreigo3cykfxazawblv7hs6wxfkprasjhsz742wsmf2osvqc7uhq4to4`.
- [Public PDS record](https://pds.oriom.dev/xrpc/com.atproto.repo.getRecord?repo=did%3Aplc%3Aveuy37bwfkvnwx43itotn4ge&collection=dev.oriom.mosimo.post&rkey=3my6exs5ek222).
- Original URI: `at://did:plc:kxwz5cz7o6g4jlmxh6doyfsm/app.bsky.feed.post/3my6es5ige22j`.
- Original CID: `bafyreiabusahy6tpoxypondbsoatm744njseuc2jto2ge7lb4ldk6mcpli`.
- Original createdAt `2026-10-18T19:48:58.187Z`; signed delivery deadline **`2026-10-18T20:48:58Z`**. Do not use after that instant to test successful fresh ingress.
- Raw tags include `type:wave-warning`, `value:advisory`, `target:jp-hokkaido`, `time:2026-10-18T19:47:00.000Z`; these are real warning/advisory data, not test alerts.

### JMA earthquake comparison

- EVENT ID: `e21acd4459b49175ad25b5c97e4e6a01672485fbf6269287aad8a5d48d10b8e2`.
- Importer PDS path: `dev.oriom.mosimo.post/3my6ex47hm222`.
- Importer record CID: `bafyreigtgpzrwdv3lkmcbyw6b3523zj422ix24uz4i6jei3c4o4a3vxl3m`.
- Original URI: `at://did:plc:vwi7zhfyamyvrg5v6ycjgzxi/app.bsky.feed.post/3my6d6ulvkx26`.
- Original CID: `bafyreihal7spi3cimxofetgjmbwygvh7oqpngssophhglqtpuzpilhkmfq`.
- Deadline **`2026-10-18T20:20:16Z`**; `type:earthquake`, `value:1`, `target:jp-kinki` (normal priority, not an emergency simulation).

Public device-worker inputs remain in **`sd_2607/appview/bsaf/private/`**: `mosimo-public-trust.json`, `IngressTrust.generated.h`, `pds-public-information.json`; these are the refreshed exact combined-scope exports with **minimum sequence 4**. Share only those public files, never the whole private directory. ESP header's public TLS CA remains empty/fail-closed: the device worker must independently provision the verified public CA and decide trusted clock/ingress enablement. No ADB, COM3, Android assets or ESP source files were touched by this deployment. Live alerts have short absolute deadlines; fetch a new genuine collected event for later device tests, never extend/re-sign an expired one as fresh.

## Validation

- `appview/bsaf`: `npm test` **34 passed**, `npm run typecheck` passed.
- `pds`: `npm test` **164 passed, 1 skipped, 0 failed**.
- Local private Windows ACL audit passed (only verified user; inheritance disabled at root); source and deployed worker key boundary validated without printing secrets.
- Normal pinned Nix build and activation succeeded; remote checkout was clean at activation, all five services active, public health/feed/web/snapshot checks passed.
- PLC canonical genesis/current key/PDS checked; public snapshot signature/freshness checked; real EVENT and record retrieval plus original-PDS CID checks passed for JMA and Kikikuru. This does not assert device receiver behavior, source repository inclusion proofs, or indefinite future service/snapshot availability.
