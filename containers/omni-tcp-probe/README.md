# Temporary Omni TCP probe

A receive-only TCP endpoint for distinguishing bicycle cellular connectivity from
failures at the production server. It never replies, authenticates a device, or
sends lock/control commands. A successful capture does not make the bicycle
online in the production management system.

## Exposure and limits

- Host: `kagoya-vps`, public IPv4 `133.18.180.180`.
- Port: **9682/TCP**, directly published by rootful Podman. No HTTP path or TLS.
- DNS: point a dedicated test hostname's **A record** at `133.18.180.180`.
  Use DNS-only mode, without a CDN/HTTP proxy. Do not add an AAAA record for this
  IPv4-only listener. The receiver does not require a particular hostname.
- This is a deliberate, temporary exception to the normal loopback/Caddy policy.
  Cellular source addresses are unknown, so this port accepts public connections.
- Maximum 8 active connections; 64 KiB captured per connection; 30 seconds idle;
  120 seconds total lifetime. The container is read-only, unprivileged, has no
  capabilities, and is limited to 64 MiB, 32 processes, and 0.25 CPU.
- JSON logs include UTC time, connection ID, peer address, exact received bytes in
  hex, and disconnect reason. Container output goes to journald; no capture file
  or additional persistent volume is created. Log retention follows host journal
  settings; per-service journal rate limiting may drop events during abuse.
- Public scanners can connect. Correlate timestamps, device IMEI/payload, and the
  recorded test action; not every incoming connection is necessarily the bike.

## Deploy and observe

Use the existing checkout on the VPS. First review its worktree, pull with
`git pull --ff-only`, then build and activate the NixOS configuration:

```sh
sudo nixos-rebuild build --flake .#kagoya-vps
sudo nixos-rebuild switch --flake .#kagoya-vps
sudo systemctl status podman-omni-tcp-probe.service --no-pager
sudo journalctl -u podman-omni-tcp-probe.service --since '10 minutes ago' --no-pager
```

Before changing the bicycle, connect from another machine and send a distinctive
non-device marker. Confirm its hex payload appears with the expected UTC time.
Opening this port in a browser is not an HTTP health check. Use a TCP client.

```powershell
Test-NetConnection TEST_HOSTNAME -Port 9682
```

After DNS and the receiver are verified, save the bicycle settings, change only
its endpoint, and confirm a fresh firmware readback. Keep APN settings unchanged
for this comparison. Restore the original endpoint and verify it after capture:

```text
Host: iot.omnibike.lycle.app101.net
Port: 9682
IPMODE: 1
```

Connection without payload already proves a TCP path from the observed source;
receiving device-identifying data strengthens attribution. Failure to connect
still requires checking DNS, setting application, firewalls, and cellular state.
No device response protocol is implemented, so disconnect/retry is expected.

## Stop and remove after the investigation

Immediate stop (also remove the container's published listener):

```sh
sudo systemctl stop podman-omni-tcp-probe.service
```

To remove the service and firewall exception persistently, remove this module's
import from `hosts/kagoya_vps/default.nix`, commit/push/pull that change, and rebuild.
Confirm the container and port listener are gone. Do not delete historical logs
until the investigation evidence has been saved.

## Local validation

No third-party Python dependencies:

```sh
python -m unittest discover -s containers/omni-tcp-probe -v
```

Tests exercise real local TCP connections: exact byte capture without a reply,
byte limits, idle and lifetime limits, and rejection of excess connections.
