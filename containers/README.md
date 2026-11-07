# Containers

Each service lives in `containers/<name>/` and owns everything about itself:
its `default.nix` module, Containerfile and source, `secrets.yaml`, and the Caddy
virtual host or firewall rule it needs. Hosts only import the module and set
`services.<name>.enable = true;` in `hosts/<node>/default.nix`.

The smallest working example is `cluster-hello`. To add a server, copy it, then:

1. change the image (pinned by `@sha256:` digest), command, and loopback port;
2. add `services.caddy.virtualHosts.<domain>` in the same module only when it needs
   public HTTP(S);
3. for an inter-node service, allow exactly that port on `tailscale0` and add the
   matching Headscale ACL in `containers/headscale/acl.hujson`;
4. for secrets, add a `creation_rules` entry in the root `.sops.yaml` for
   `containers/<name>/secrets.yaml` (operator + the host that runs it), then
   `./bin/secret-edit.sh <name>`;
5. import it in the intended host and enable it.

## Rules enforced at evaluation time

`modules/container-policy.nix` fails `nix flake check` and every host build when:

- a container publishes a port on a non-loopback address without listing itself in
  `cluster.containerPolicy.publicPortContainers` (declared next to its firewall rule);
- two containers publish the same host port;
- a registry image is not pinned by digest.

Images built from this repository use `lib/local-image.nix`: the tag is derived from
the build context, and the host builds only when that tag is missing, so restarts do
not depend on registries or npm being reachable.

## Exceptions

Temporary: `omni-tcp-probe` exposes 9682/TCP publicly as a receive-only probe for
checking external connectivity. It is not a web service. See its README for capture
limits and removal instructions.

External implementations are also exposed through a local `containers/<name>/default.nix`
(see `mosimo`). The local module owns deployment-specific domains, secrets, and routes,
so hosts never import paths from an external repository directly.
