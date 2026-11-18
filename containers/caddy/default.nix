{ pkgs, ... }:
{
  # Native Caddy is the only public HTTP(S) entry point. Each service module adds its
  # own `services.caddy.virtualHosts.<domain>` next to the container it fronts.
  services.caddy.enable = true;

  # caddy-l4 lets :80 hand connections that are not HTTP/1.x (HTTP/0.9 for oriom.dev)
  # to another listener; everything else is served by Caddy exactly as before.
  # Pinned to the release whose go.mod accepts nixpkgs' Caddy (2.11.2); bump them together.
  services.caddy.package = pkgs.caddy.withPlugins {
    plugins = [ "github.com/mholt/caddy-l4@v0.1.0" ];
    hash = "sha256-/AxtpMmEvYvbxTSOvANv5wRx/6shTYi/l29L7kRTgE4=";
  };
}
