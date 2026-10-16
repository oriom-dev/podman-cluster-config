{ ... }:
{
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8080;
    settings = {
      server_url = "https://headscale.oriom.dev";
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
      };
      dns = {
        magic_dns = true;
        base_domain = "ts.home.arpa";
        nameservers.global = [ "1.1.1.1" ];
      };
      policy.path = ./acl.hujson;
    };
  };
}