{ ... }:
{
  services.caddy = {
    enable = true;
    virtualHosts = {
      "headscale.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:8080
      '';
      "pds.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:2583
      '';
      "appview.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:3000
      '';
    };
  };
}