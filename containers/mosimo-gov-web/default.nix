# Mosimo post review dashboard for government offices (gov.mosimo.oriom.dev), from
# jphacks/sd_2607. Built with Vite at Nix build time and served by Caddy as static
# files; talks to the AppView over HTTPS only.
{ config, inputs, lib, ... }:
{
  imports = [ (inputs.mosimo + "/apps/gov-web") ];

  config = lib.mkIf config.services.mosimo-gov-web.enable {
    services.mosimo-gov-web = {
      domain = "gov.mosimo.oriom.dev";
      appviewUrl = "https://appview.oriom.dev";
    };
  };
}
