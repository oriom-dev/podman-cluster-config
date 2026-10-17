{ ... }:
{
  services.caddy = {
    enable = true;
    virtualHosts = {
      "headscale.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:8080
      '';
      "hello.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:3000
      '';
    };
  };
}