# Containers

Each service lives in `containers/<name>/default.nix` and is imported only by the host that runs it. The smallest working example is `cluster-hello`: it runs on `kagoya-vps`, binds TCP/3000 to loopback only, and Caddy is its public entry point.

To add a server, copy `containers/cluster-hello`, change its image, command, and port, then:

1. import it in the intended `hosts/<node>/default.nix`;
2. bind a VPS-local service to loopback and add a Caddy virtual host only when it needs public HTTP(S);
3. for an inter-node service, allow exactly that port on `tailscale0` and add the matching Headscale ACL.

Do not publish application ports on the VPS. Caddy is the sole public web entry point; inter-node traffic uses the host Tailscale interface and Headscale ACLs.

## Containers from another public repository

Add the public monorepo as a non-flake input in `flake.nix`. `flake.lock` pins the resolved revision, so deployment does not follow an unreviewed branch update.

```nix
inputs.external-services = {
  url = "github:OWNER/REPOSITORY";
  flake = false;
};
```

An external service directory needs a `default.nix` NixOS module. Relative paths, such as `./Containerfile`, are resolved within that directory.

```nix
# containers/hello-world/default.nix in OWNER/REPOSITORY
{ ... }:
{
  virtualisation.oci-containers.containers.hello-world = {
    image = "docker.io/hashicorp/http-echo:1.0";
    cmd = [ "-listen=:5678" "-text=hello" ];
    ports = [ "127.0.0.1:3000:5678" ];
  };
}
```

Import one external directory in the target host, then keep the host-specific firewall, Headscale ACL, and public Caddy route in this repository:

```nix
# hosts/kagoya_vps/default.nix
{ inputs, ... }:
{
  imports = [
    # existing imports...
    (inputs.external-services + "/containers/hello-world")
  ];
}
```

After changing the input, run `nix flake lock --update-input external-services`, review `flake.lock`, and build the affected host before deployment.
