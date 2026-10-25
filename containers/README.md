# Containers

Each service lives in `containers/<name>/default.nix` and is imported only by the host that runs it. The smallest working example is `cluster-hello`: bind a VPS-local service to loopback and use Caddy as its public entry point.

To add a server, copy `containers/cluster-hello`, change its image, command, and port, then:

1. import it in the intended `hosts/<node>/default.nix`;
2. bind a VPS-local service to loopback and add a Caddy virtual host only when it needs public HTTP(S);
3. for an inter-node service, allow exactly that port on `tailscale0` and add the matching Headscale ACL.

Do not publish application ports on the VPS. Caddy is the sole public web entry point; inter-node traffic uses the host Tailscale interface and Headscale ACLs.

Temporary exception: `omni-tcp-probe` exposes only 9682/TCP for a receive-only cellular connectivity investigation. It is not a web service. See its README for capture limits and removal instructions; remove its host import after the investigation.

External implementations are also exposed through a local `containers/<name>/default.nix`. The local module owns deployment-specific domains, secrets, and routes, so hosts never import paths from an external repository directly.
