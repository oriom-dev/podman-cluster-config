{ ... }:
{
  # Native Caddy is the only public HTTP(S) entry point. Each service module adds its
  # own `services.caddy.virtualHosts.<domain>` next to the container it fronts.
  services.caddy.enable = true;
}
