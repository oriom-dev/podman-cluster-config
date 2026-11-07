# Mosimo web client (mosimo.oriom.dev), from jphacks/sd_2607. Static files served
# by Caddy; talks to the AppView over HTTPS only.
{ config, inputs, lib, ... }:
{
  imports = [ (inputs.mosimo + "/apps/web") ];

  config = lib.mkIf config.services.mosimo-web.enable {
    services.mosimo-web = {
      domain = "mosimo.oriom.dev";
      appviewUrl = "https://appview.oriom.dev";
      # Public HappyView API client key (shipped to browsers), registered in HappyView.
      clientKey = "hvc_c15d9393de6ace328d65633d07d00278";
    };
  };
}
