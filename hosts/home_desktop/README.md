# home-desktop

NixOS Hyper-V Gen2 VM on the desktop-1 Windows host (Ryzen 7 5700X, 48 GB).
It replaced the roadmap's NixOS-WSL plan: every WSL2 distribution shares one VM,
kernel and network namespace with the owner's other distributions, and interop
reaches Windows as an administrator. That cannot isolate Internet-facing workloads.

| | |
|---|---|
| vCPU / RAM | 4 (scheduling weight 50, at most 75 %) / 8 GiB static |
| System disk | `C:\HyperV\home-desktop\home-desktop.vhdx`, 64 GB, NVMe |
| Data disk | `S:\HyperV\home-desktop\home-desktop-data.vhdx`, 512 GB, HDD → `/srv/data` |
| Network | internal switch `oriom-node` + WinNAT, VM `10.250.0.2/24`, host `10.250.0.1` |
| Start | Hyper-V automatic start at host boot (no login), shutdown with the host |
| Recovery | Task `home-desktop-recovery` (SYSTEM, every 5 min) starts the VM if it is not running. Create `C:\HyperV\home-desktop\maintenance` to keep it down on purpose |

## Isolation (host-enforced)

`provision.ps1` puts extended port ACLs on the VM's NIC. Root inside the VM cannot
change them. The VM may only open TCP/UDP connections to public IPv4 addresses.
All private, CGNAT (Tailscale), loopback, link-local, multicast and reserved IPv4
ranges and all IPv6 are denied in both directions. The single exception is inbound
SSH from the Windows host (`10.250.0.1` → `:22`).

Probe matrix run from the VM on 2026-11-07 (outbound is not filtered inside the VM,
so every "blocked" comes from the host ACL):

| Target | Result |
|---|---|
| Internet HTTPS, DNS (1.1.1.1) | open |
| Host via gateway 10.250.0.1 (22, 445, 3389, ICMP) | blocked |
| Host LAN / Wi-Fi 192.168.150.101/.106:22, router 192.168.150.1 | blocked |
| Host Windows tailnet 100.83.13.105:22 | blocked |
| WSL switch 172.26.208.1, Default Switch 172.24.160.1, Surfshark 10.7.7.1 | blocked |

Re-run the matrix after any change to Windows, Hyper-V, the switch or the ACLs.

## Management path

`chiba@desktop-1` (Windows OpenSSH, administrator) is the only way in. It is a
high-privilege path and must stay separate from workloads: nothing in the VM may
reach the host (see above).

```sh
ssh -F hosts/home_desktop/ssh_config home-desktop   # ProxyJump via desktop-1
```

`hosts/home_desktop/ssh_config` and `ssh_known_hosts` are local files (gitignored).

## First install / rebuild of the VM

```sh
nix build .#home-desktop-image                     # 8 GB VHDX, grows on first boot
scp result/*.vhdx chiba@desktop-1:C:/HyperV/staging/home-desktop-image.vhdx
scp hosts/home_desktop/provision.ps1 chiba@desktop-1:C:/HyperV/staging/
ssh chiba@desktop-1 powershell -ExecutionPolicy Bypass -File C:\HyperV\staging\provision.ps1 -ImagePath C:\HyperV\staging\home-desktop-image.vhdx
ssh chiba@desktop-1 powershell Start-VM home-desktop
# once: format the data disk
ssh -F hosts/home_desktop/ssh_config home-desktop sudo mkfs.ext4 -L data /dev/sdb
```

The SSH host key, and with it the sops age recipient `home_desktop`
(`ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`), is created on first boot. A
reinstall changes it: update `.sops.yaml` and run `sops updatekeys`.
