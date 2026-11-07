#!/usr/bin/env bash
# Enrolls a node into the Headscale tailnet with a tagged, single-use pre-auth key
# that expires in 10 minutes (roadmap M2). The key goes from Headscale to the node
# through this pipe only; it is never printed or stored in the repository.
#
#   ./bin/tailnet-enroll.sh kagoya_vps1 tag:ingress kagoya-vps
#   ./bin/tailnet-enroll.sh home-desktop tag:worker home-desktop -F hosts/home_desktop/ssh_config
#
# The tag comes from the pre-auth key. Do not also pass --advertise-tags: Headscale
# then checks tagOwners for the (non-existent) owning user and rejects the node.
#
# Preferences set here persist in the node's tailscaled state:
#   --accept-dns=false     keep the host's resolvers (Podman uses *.ts.home.arpa aliases)
#   --netfilter-mode=off   leave packet filtering to the NixOS firewall
set -euo pipefail

[[ $# -ge 3 ]] || { echo 'usage: tailnet-enroll.sh SSH_TARGET TAG HOSTNAME [SSH_OPTION...]' >&2; exit 1; }
target=$1 tag=$2 name=$3
shift 3
headscale_host=${HEADSCALE_SSH:-kagoya_vps1}
login_server=${HEADSCALE_URL:-https://headscale.oriom.dev}

[[ $tag =~ ^tag:[a-z0-9-]+$ && $name =~ ^[a-z0-9-]+$ ]] || { echo 'invalid tag or hostname' >&2; exit 1; }

ssh -o BatchMode=yes "$headscale_host" \
  "sudo -n headscale preauthkeys create --tags $tag --expiration 10m -o json-line" |
  sed -n 's/.*"key":"\([^"]*\)".*/\1/p' |
  ssh -o BatchMode=yes "$@" "$target" "
    set -eu
    umask 077
    f=\$(mktemp)
    trap 'shred -u \"\$f\"' EXIT
    cat > \"\$f\"
    [ -s \"\$f\" ] || { echo 'no pre-auth key received' >&2; exit 1; }
    sudo -n tailscale up --login-server=$login_server --auth-key=file:\$f \
      --hostname=$name --reset \
      --accept-dns=false --netfilter-mode=off --timeout=60s
    tailscale ip -4
  "
