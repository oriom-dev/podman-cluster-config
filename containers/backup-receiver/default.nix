# Append-only restic REST server on home-desktop: the off-host copy of kagoya-vps
# backups (containers/backup pushes here).
#
# - Reachable only over the tailnet (tailscale0), and the Headscale ACL lets only
#   tag:ingress reach port 8000.
# - Append-only: a compromised kagoya-vps can add snapshots but not delete or rewrite
#   existing ones.
# - Repositories are encrypted with kagoya-vps's restic password, which this node
#   never has; it stores ciphertext only.
#
# Old snapshots are not pruned here (append-only forbids it, and pruning needs the
# password). Restic deduplicates, so growth is the daily delta; prune from the
# operator workstation when /srv/data needs space.
{ config, ... }:
let
  port = 8000;
in
{
  sops.secrets.restic_htpasswd = {
    sopsFile = ./secrets.yaml;
    format = "yaml";
    owner = "restic";
    mode = "0400";
    restartUnits = [ "restic-rest-server.service" ];
  };

  services.restic.server = {
    enable = true;
    # Socket-activated; the module expects a bare port.
    listenAddress = toString port;
    dataDir = "/srv/data/restic";
    appendOnly = true;
    privateRepos = true;
    htpasswd-file = config.sops.secrets.restic_htpasswd.path;
  };

  systemd.services.restic-rest-server.unitConfig.RequiresMountsFor = [ "/srv/data" ];

  # Not on eth0: the only inbound path there is SSH from the Windows host.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
