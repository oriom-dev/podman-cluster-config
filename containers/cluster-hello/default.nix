{ ... }:
{
  # This is the minimal container example. Copy this directory to add a service.
  virtualisation.oci-containers.containers.cluster-hello = {
    image = "docker.io/hashicorp/http-echo:1.0";
    cmd = [ "-listen=:5678" "-text=hello from kagoya-vps" ];
    ports = [ "127.0.0.1:3001:5678" ];
  };
}
