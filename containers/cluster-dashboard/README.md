# cluster-dashboard

Shows active nodes, which containers run where, and how much CPU, memory,
storage and network each container and native service uses against its limit and
the node's remaining capacity. One hour of history is kept in memory.

```
 tag:host / tag:mobile ──(Tailscale tailnet oriom-dev.github, svc:dashboard tcp:80)──┐
                                                                                      ▼
 kagoya-vps ┌─ netns of container cluster-dashboard ──────────────────────────────────────┐
            │  cluster-dashboard-ts (userspace tailscaled, tag:svc) ─→ 127.0.0.1:8080       │
            │  cluster-dashboard (server.py, UI, 1 h history)                              │
            └──────────── /run/cluster-dashboard/agent.sock (ro, group-only) ──────────────┘
            cluster-dashboard-agent (native, root, read-only, collector)
                │  pulls /v1/node over Headscale tailscale0 (ACL: tag:ingress → tag:worker:9925)
 home-desktop   ▼  cluster-dashboard-agent (native, listens on tailscale0:9925 only)
```

| Part | Where | Notes |
|---|---|---|
| `agent.py` | every node with `services.cluster-dashboard.agent.enable` | `/proc`, cgroup v2, `podman ps/inspect`, `du` every 10 min. Never changes anything |
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

## Tailscale tailnet policy (admin console, done by the operator)

1. Access controls → add (merge into the existing policy):

   ```jsonc
   "tagOwners": {
     "tag:svc": ["autogroup:admin"]
   },
   "grants": [
     {"src": ["tag:host", "tag:mobile"], "dst": ["svc:dashboard"], "ip": ["tcp:80"]}
   ],
   "autoApprovers": {
     "services": {"svc:dashboard": ["tag:svc"]}
   }
   ```

   Make sure no existing rule grants `*` or `tag:host`/`tag:mobile` → `tag:svc`
   beyond this; the sidecar serves nothing on its own device address anyway.
2. Services → define `svc:dashboard` with port `tcp:80`.
3. First login of the sidecar (once; state persists in
   `/var/lib/cluster-dashboard/tailscale`):

   ```sh
   ssh kagoya_vps1 sudo journalctl -u podman-cluster-dashboard-ts | grep -o 'https://login.tailscale.com/a/[^ ]*' | tail -1
   ```

   Open the URL as a tailnet admin. The device registers as `cluster-dashboard`
   with `tag:svc` (tagged devices do not expire). Alternatively set
   `services.cluster-dashboard.tailscale.environmentFile` to a sops env file with
   `TS_AUTHKEY=` for unattended login.

Then open `http://dashboard.<tailnet>.ts.net/` from a `tag:host` or `tag:mobile`
device.

## Adding a node

Import this module, set `services.cluster-dashboard.agent = { enable = true;
listenTailnet = true; }`, and add `tag:ingress → <node tag>:9925` to
`containers/headscale/acl.hujson`. The collector finds the node via `tailscale status`.

## Tests

```sh
python3 -m unittest -v test_dashboard.py
```
