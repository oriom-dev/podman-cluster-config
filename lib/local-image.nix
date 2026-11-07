# Builds a Containerfile on the host for virtualisation.oci-containers.
#
# The tag is derived from the build context's store path, so it changes exactly when
# a file in the context changes. preStart builds only when that tag is missing, which
# lets restarts and reboots reuse the image without registry or npm access.
#
# Usage:
#   let img = import ../../lib/local-image.nix { inherit lib; podman = ...; } {
#     name = "jpost-api";
#     context = lib.fileset.toSource { root = ./.; fileset = ...; };
#   };
#   in { ...containers.<name>.image = img.image; systemd.services.<unit>.preStart = img.preStart; }
{ lib, podman }:
{ name, context, containerfile ? "Containerfile" }:
let
  contextPath = builtins.unsafeDiscardStringContext "${context}";
  tag = builtins.substring 0 32 (builtins.hashString "sha256" contextPath);
  image = "localhost/${name}:${tag}";
in
{
  inherit image;

  preStart = ''
    if ! ${podman}/bin/podman image exists ${lib.escapeShellArg image}; then
      ${podman}/bin/podman build \
        --tag ${lib.escapeShellArg image} \
        --file ${context}/${containerfile} \
        ${context}
    fi
  '';
}
