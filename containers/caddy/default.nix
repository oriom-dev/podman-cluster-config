{ ... }:
{
  services.caddy = {
    enable = true;
    virtualHosts = {
      "headscale.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:8080
      '';
      "pds.oriom.dev".extraConfig = ''
        handle /.well-known/mosimo/trust/snapshot.cbor {
          root * /var/lib/mosimo-trust
          rewrite * /snapshot.cbor
          header Content-Type application/cbor
          header Cache-Control "no-store"
          file_server
        }
        handle {
          reverse_proxy 127.0.0.1:2583
        }
      '';
      "appview.oriom.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:3000
      '';
    };
  };
}