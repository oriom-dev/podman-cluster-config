# Evaluation-time guards for virtualisation.oci-containers on every host.
#
# - Host ports bind to loopback; Caddy or Tailscale is the way in. A module that must
#   listen publicly lists its container in `cluster.containerPolicy.publicPortContainers`
#   next to the firewall rule, so the exception is reviewed where it is introduced.
# - No two containers publish the same host port.
# - Registry images are pinned by digest; `localhost/` images are built from this
#   repository with a content-derived tag (lib/local-image.nix).
{ config, lib, ... }:
let
  cfg = config.cluster.containerPolicy;
  containers = config.virtualisation.oci-containers.containers;

  # "[ip:]hostPort:containerPort[/proto]" -> { ip, hostPort, proto }
  parsePort = spec:
    let
      protoParts = lib.splitString "/" spec;
      proto = if builtins.length protoParts > 1 then lib.last protoParts else "tcp";
      body = builtins.head protoParts;
      v6 = builtins.match "\\[([^]]*)]:([^:]*):(.*)" body;
      parts = lib.splitString ":" body;
    in
    if v6 != null then { ip = builtins.elemAt v6 0; hostPort = builtins.elemAt v6 1; inherit proto; }
    else if builtins.length parts == 3 then { ip = builtins.elemAt parts 0; hostPort = builtins.elemAt parts 1; inherit proto; }
    else if builtins.length parts == 2 then { ip = ""; hostPort = builtins.elemAt parts 0; inherit proto; }
    else { ip = ""; hostPort = body; inherit proto; };

  isLoopback = ip: lib.hasPrefix "127." ip || ip == "::1" || ip == "localhost";

  published = lib.concatLists (lib.mapAttrsToList
    (name: c: map (spec: (parsePort spec) // { inherit name spec; }) c.ports)
    containers);

  nonLoopback = builtins.filter
    (p: !(isLoopback p.ip) && !(builtins.elem p.name cfg.publicPortContainers))
    published;

  byHostPort = lib.groupBy (p: "${p.hostPort}/${p.proto}") published;
  conflicts = lib.filterAttrs
    (_: ps: builtins.length (lib.unique (map (p: p.name) ps)) > 1)
    byHostPort;

  unpinned = lib.filterAttrs
    (_: c: !(lib.hasPrefix "localhost/" c.image) && !(lib.hasInfix "@sha256:" c.image))
    containers;
in
{
  options.cluster.containerPolicy.publicPortContainers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Containers allowed to publish host ports on non-loopback addresses.";
  };

  config.assertions = [
    {
      assertion = nonLoopback == [ ];
      message = "containers publish non-loopback ports without an exception: "
        + lib.concatMapStringsSep ", " (p: "${p.name} (${p.spec})") nonLoopback;
    }
    {
      assertion = conflicts == { };
      message = "host ports published by more than one container: "
        + lib.concatStringsSep ", " (lib.mapAttrsToList
          (port: ps: "${port} <- ${lib.concatMapStringsSep "," (p: p.name) ps}") conflicts);
    }
    {
      assertion = unpinned == { };
      message = "container images must be pinned by @sha256 digest: "
        + lib.concatStringsSep ", " (lib.mapAttrsToList (n: c: "${n} (${c.image})") unpinned);
    }
  ];
}
