# cluster-dashboard

Shows active nodes, which containers run where, and how much CPU, memory,
storage and network each container and native service uses against its limit and
the node's remaining capacity. One hour of history is kept in memory.

```
 tag:host / tag:mobile ──(Tailscale tailnet oriom-dev.github, svc:dashboard https:443)─┐
                                                                                      ▼
 kagoya-vps ┌─ netns of container cluster-dashboard ──────────────────────────────────────┐
            │  cluster-dashboard-ts (userspace tailscaled, tag:svc) ─→ 127.0.0.1:8080       │
            │  cluster-dashboard (server.py, UI, 1 h history)                              │
            └──────────── /run/cluster-agent/agent.sock (ro, group-only) ────────────────┘
            cluster-agent (native, root, read-only, collector)
                │  pulls /v1/node over Headscale tailscale0 (ACL: tag:ingress → tag:worker:9925)
 home-desktop   ▼  cluster-agent (native, listens on tailscale0:9925 only)
```

| Part | Where | Notes |
|---|---|---|
| `agent.py` | every node with `services.cluster-dashboard.agent.enable` | `/proc`, cgroup v2, `podman ps/inspect`, `du` every 10 min, `systemctl show`, `ss -ltnp`, Caddy admin API (read only). Never changes anything |
| collector | the node with `services.cluster-dashboard.enable` | the local agent also pulls every peer listed by `tailscale status` |
| `app/` | container `cluster-dashboard` | stdlib Python on the pinned `python:3.13-alpine`; only the agent socket is mounted |
| sidecar | container `cluster-dashboard-ts` | `tailscale/tailscale` in userspace mode, no capabilities, in the dashboard's netns |

The sidecar joins the operator's **Tailscale** tailnet, not the Headscale cluster
tailnet, so the dashboard is reachable from operator devices while nothing else in
the cluster becomes reachable from them. The page is not on Caddy and has no public
port; `127.0.0.1:3010` exists for SSH tunnels:

```sh
ssh -L 3010:127.0.0.1:3010 kagoya_vps1   # then http://127.0.0.1:3010/
```

## Health, relations and HTTP requests

- Container health comes from the Podman status (`healthy` / `unhealthy` / `starting`);
  containers without a healthcheck count as running. A restart within the last hour
  (`NRestarts` of `podman-<name>.service`) shows as RESTARTED.
- Hovering a container or service highlights the units it is related to: systemd
  dependencies (`Requires`, `Wants`, `BindsTo`, `PartOf`, `Requisite`, `Upholds`, both
  directions) and Caddy → the unit listening on each `reverse_proxy` upstream port.
- Where Caddy runs, the module turns on its `metrics { per_host }` option. The agent reads
  `caddy_http_request_duration_seconds_count` from `localhost:2019/metrics`. For each
  site it uses only the busiest handler, because Caddy counts a request once for every
  instrumented handler in the chain. It attributes each site to its upstream unit; the
  `caddy` row shows all sites. REQ/S is the current rate. 5XX is the share of 5xx responses
  over the last hour; the 4xx share and the hosts are in the hover title. Only HTTP
  through Caddy is counted: raw TCP (Minecraft) and the tailnet-only dashboard are not.

## Tailscale tailnet policy (admin console, done by the operator)

1. Access controls → add (merge into the existing policy):

   ```jsonc
   "tagOwners": {
     "tag:svc": ["autogroup:admin"]
   },
   "grants": [
     {"src": ["tag:host", "tag:mobile"], "dst": ["svc:dashboard"], "ip": ["tcp:443"]}
   ],
   "autoApprovers": {
     "services": {"svc:dashboard": ["tag:svc"]}
   }
   ```

   Make sure no existing rule grants `*` or `tag:host`/`tag:mobile` → `tag:svc`
   beyond this; the sidecar serves nothing on its own device address anyway.
2. Services → define `svc:dashboard` with port `tcp:443`, and DNS → enable HTTPS Certificates
   (MagicDNS is required). Tailscale then issues and renews the Let's Encrypt certificate for
   `dashboard.<tailnet>.ts.net`; the name appears in public Certificate Transparency logs.
3. First login of the sidecar: Settings → Keys → generate an auth key with tag
   `tag:svc`, **not** reusable, pre-approved, short expiry. Put it in the secret and
   deploy:

   ```sh
   ./bin/secret-edit.sh cluster-dashboard   # TS_AUTHKEY=tskey-auth-...
   ```

   It is used only while the node is logged out (`TS_AUTH_ONCE`); the node state
   then persists in `/var/lib/cluster-dashboard/tailscale` and tagged devices do not
   expire, so the spent key can stay. If that directory is lost, issue a new key.
   Interactive login does not work: containerboot kills `tailscale up` after 60 s
   and the container restarts with a new login URL.

Then open `https://dashboard.<tailnet>.ts.net/` from a `tag:host` or `tag:mobile`
device.

## Adding a node

Import this module, set `services.cluster-dashboard.agent = { enable = true;
listenTailnet = true; }`, and add `tag:ingress → <node tag>:9925` to
`containers/headscale/acl.hujson`. The collector finds the node via `tailscale status`.

## Tests

```sh
python3 -m unittest -v test_dashboard.py
```
