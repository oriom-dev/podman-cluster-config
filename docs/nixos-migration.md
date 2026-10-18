# NixOS migration

## Kagoya VPS

`kagoya-vps` replaces the current Ubuntu disk. It is intentionally destructive: `hosts/kagoya_vps/disko.nix` repartitions `/dev/vda` as a 1 GiB EFI System Partition and an ext4 root filesystem.

1. On the workstation, ensure `ssh kagoya_default_podman` reaches `133.18.180.180` as `ubuntu`. The dedicated deployment key is declared for the NixOS `operator` account in `hosts/kagoya_vps/default.nix`; keep its private half outside Git.
2. Set an A record (not AAAA until IPv6 is configured) for `headscale.oriom.dev` to `133.18.180.180`, before starting the install. Caddy needs TCP 80/443 reachable for ACME.
3. From the repository root, run:

   ```sh
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#kagoya-vps \
     --target-host ubuntu@133.18.180.180 \
     --copy-host-keys
   ```

   This copies the configuration, kexecs into NixOS, formats `/dev/vda`, and installs the new system. Keep the Kagoya console open: incorrect network settings can otherwise lock out SSH.
4. After the new system boots, log in as `operator`, then join its host Tailscale client to Headscale. Do not put an auth key in Git:

   ```sh
   ssh -i ~/.ssh/kagoya_nixos operator@133.18.180.180
   sudo tailscale up --login-server https://headscale.oriom.dev --hostname kagoya-vps
   ```

## Mosimo PDS on Kagoya VPS

`flake.nix` pins the external `jphacks/sd_2607` non-flake input; the VPS imports its `pds` module. The service runs natively as `mosimo-pds` with Node.js 24 and SQLite, without an OCI registry or separate database process. Caddy forwards `https://pds.oriom.dev` to loopback port 2583; set its DNS A record to `133.18.180.180` before activation.

SQLite data lives in `/var/lib/mosimo-pds/pds.sqlite` on the VPS's persistent local disk. This is a single-node deployment: never share this file over a network filesystem or load-balance the same logical PDS across independent databases. The PDS has a 256 MiB Node old-space limit and systemd `MemoryHigh=384M` / `MemoryMax=512M`; measure actual usage alongside other services on the 3 GiB VPS.

The VPS collects protocol kind-1 events and kind-5 deletion requests from `wss://relay.damus.io`. The pinned runtime includes fixes for the real PLC Directory response format and upstream history backpressure. Production verification on 2026-10-18 covered eight signed commits, out-of-order recovery, MST/CAR/firehose integrity, history and fresh live collection from Damus, and persistence after restarting the service. This is not a generic Nostr relay (only kinds 1/5 are accepted); `bsky.network` rejected its crawl request, so external atproto Relay ingestion is not yet compatible. See the [production verification report](https://github.com/jphacks/sd_2607/blob/main/docs/pds-production-verification-2026-10-18.md) for evidence and limitations.

After reviewing input updates, build locally, then activate on the VPS:

```sh
nix build .#nixosConfigurations.kagoya-vps.config.system.build.toplevel
sudo nixos-rebuild switch --flake .#kagoya-vps
systemctl status mosimo-pds
curl http://127.0.0.1:2583/health
curl https://pds.oriom.dev/health
```

Do not bypass SSH host-key verification to deploy. Confirm any changed key through the VPS console or another trusted channel first. Back up SQLite with its online backup API (for example, `sqlite3 .backup`) or stop the service before copying the database and any WAL/SHM files consistently. Never restore an older database under the same public endpoint without resolving firehose sequence continuity. See the imported `pds/deployment.md` for detailed backup and PostgreSQL opt-in instructions.

## Home desktop (NixOS-WSL)

Import a NixOS-WSL release, then apply this repository's configuration from inside the NixOS WSL distribution:

```sh
sudo nixos-rebuild switch --flake /path/to/podman-cluster-config#home-desktop
sudo tailscale up --login-server https://headscale.oriom.dev --hostname home-desktop
```

WSL2 NAT keeps the Linux instance off the LAN, but Windows owns the outer firewall and localhost forwarding. Keep `wsl2.localhostForwarding=false` in `%UserProfile%\.wslconfig` if Windows applications must not reach services in WSL, and enforce equivalent inbound restrictions with Windows Firewall. NixOS cannot manage those Windows controls.

## Headscale policy and node enrollment

The checked-in policy starts deny-by-default and permits only the ingress node to call worker HTTP services on TCP/3000. Create the `cluster` Headscale user, issue tagged pre-auth keys, and add ports deliberately as new services are introduced. Never commit auth keys, SOPS private keys, or a generated Headscale database.
