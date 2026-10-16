{ ... }:
{
  # This is the minimal cross-node example. Copy this directory to add a service.
  virtualisation.oci-containers.containers.cluster-hello = {
    image = "docker.io/hashicorp/http-echo:1.0";
    cmd = [ "-listen=:5678" "-text=hello from home-desktop" ];
    ports = [ "3000:5678" ];
  };
}
