# Containers

Each service lives in `containers/<name>/default.nix` and is imported only by the host that runs it. The smallest working example is `cluster-hello`: it runs on `home-desktop`, exposes TCP/3000 only through `tailscale0`, and Caddy on `kagoya-vps` reaches it over MagicDNS.

To add a server, copy `containers/cluster-hello`, change its image, command, and port, then:

1. import it in the intended `hosts/<node>/default.nix`;
2. allow exactly that port on `networking.firewall.interfaces.tailscale0` for the target node;
3. add the matching source, destination port, and tag to `containers/headscale/acl.hujson`;
4. add the public Caddy virtual host only when the service needs public HTTP(S).

Do not publish application ports on the VPS. Caddy is the sole public web entry point; inter-node traffic uses the host Tailscale interface and Headscale ACLs.
