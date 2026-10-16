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

## Home desktop (NixOS-WSL)

Import a NixOS-WSL release, then apply this repository's configuration from inside the NixOS WSL distribution:

```sh
sudo nixos-rebuild switch --flake /path/to/podman-cluster-config#home-desktop
sudo tailscale up --login-server https://headscale.oriom.dev --hostname home-desktop
```

WSL2 NAT keeps the Linux instance off the LAN, but Windows owns the outer firewall and localhost forwarding. Keep `wsl2.localhostForwarding=false` in `%UserProfile%\.wslconfig` if Windows applications must not reach services in WSL, and enforce equivalent inbound restrictions with Windows Firewall. NixOS cannot manage those Windows controls.

## Headscale policy and node enrollment

The checked-in policy starts deny-by-default and permits only the ingress node to call worker HTTP services on TCP/3000. Create the `cluster` Headscale user, issue tagged pre-auth keys, and add ports deliberately as new services are introduced. Never commit auth keys, SOPS private keys, or a generated Headscale database.
