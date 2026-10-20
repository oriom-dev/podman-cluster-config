# Deployment record — 2026-10-20

## Scope

Temporary, receive-only TCP probe on `kagoya-vps` (`133.18.180.180:9682`).
The bicycle's endpoint and APN settings were **not changed during deployment**.
DNS remains a user action; no test hostname is assumed to exist yet.

## Source and deployment

- Implementation commit: `46abd8a` (`Add temporary Omni TCP connectivity probe`).
- Pushed to `origin/main` in `oriom-dev/podman-cluster-config`.
- SSH: existing `kagoya_vps1` alias, user `operator`.
- Remote checkout: `/home/operator/podman-cluster-config`, initially clean at
  `da82f21`; updated using `git pull --ff-only`.
- The local worktree's pre-existing deletions of three `docs/` files were left
  untouched and excluded from the commit.
- Built with `sudo nixos-rebuild build --flake /home/operator/podman-cluster-config#kagoya-vps`.
- Reviewed `nix store diff-closures` and the systemd directory diff: only the new
  probe and firewall configuration changed; no existing application unit changed.
- Pulled `docker.io/library/python:3.13-alpine` and activated with
  `sudo nixos-rebuild switch --flake /home/operator/podman-cluster-config#kagoya-vps`.
- Service active from **2026-10-20 07:39:31 UTC**.
- Receiver's `listen` log: **2026-10-20 07:39:33.365011 UTC**.

Previous system (rollback reference):

```text
/nix/store/k26z15ddamcdbdw7gw0q3vvdkkxa4092-nixos-system-kagoya-vps-26.05.20260409.4c1018d
```

Activated system:

```text
/nix/store/bz9j9kchmpafhqff21s50fxdhwy0dkyx-nixos-system-kagoya-vps-26.05.20260409.4c1018d
```

Observed image digest:

```text
sha256:ba27df8b6499cc3756cff167690f3fcb5321faa1703b3a914df5f4fdadb32f05
```

The configuration uses a version tag; the digest records the image used for this
run, rather than claiming the tag is immutable.

## Validation

- Local Python 3.10: all four socket integration tests passed.
- VPS Python 3.13 image, read-only unprivileged container with `--network=none`:
  all four tests passed. These use container-local loopback only.
- External PC connected to the **public** `133.18.180.180:9682` and sent:

```text
OMNI-PROBE-PC-20261020\n
```

- Receiver logged connection, **23 bytes**, exact hex, and EOF/disconnect at
  **2026-10-20 07:41:40 UTC**:

```text
4f4d4e492d50524f42452d50432d32303236313032300a
```

- Peer recorded by the receiver: `124.209.66.45:52942` (PC test, **not the bike**).
- No response bytes were returned, as designed.
- `ss` confirmed `0.0.0.0:9682` listening.
- `caddy`, `headscale`, `podman-happyview`, and `podman-omni-tcp-probe` all active.
- Existing `happyview` container retained its uptime (not restarted).
- `systemctl --failed` showed zero failed units after activation.

## DNS and next test

Create an **A record** for a dedicated test hostname pointing to:

```text
133.18.180.180
```

DNS-only; no CDN/HTTP proxy; no AAAA for this IPv4-only listener. Device target
port stays **9682/TCP**. Tell the investigator the exact FQDN after setting DNS.
The receiver has no HTTP URL path and no TLS.

Before changing the bicycle, resolve that hostname and repeat the PC marker test.
Then save/read back the existing device endpoint and change only the endpoint,
keeping the SIM/APN configuration unchanged. Correlate device logs and server
logs, and restore the original endpoint afterward. See README for stop/removal.
