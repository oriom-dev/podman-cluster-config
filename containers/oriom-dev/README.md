# oriom-dev

The portfolio at <https://oriom.dev>, from [oriom-dev/oriom-dev](https://github.com/oriom-dev/oriom-dev).
The repository's NixOS module (`nixosModules.default`) runs the Node.js server in a
`node:24-alpine` container with the built site mounted read-only from the Nix store;
`default.nix` here only picks ports, the domain and the agent socket.

| Protocol | Path |
|---|---|
| HTTP/1.0, 1.1, 2, 3 | Caddy (`oriom.dev`, also plain `http://oriom.dev` without a redirect) → `127.0.0.1:3020` |
| HTTP/0.9 | `:80` → caddy-l4 listener wrapper (`../caddy`) → PROXY v2 → `127.0.0.1:3021` |
| CoAP | UDP `5683`, published directly (listed in `publicPortContainers`) |

Only connections on `:80` that are not HTTP/1.x go to the HTTP/0.9 port; every other
request, ACME HTTP-01 included, is served by Caddy as before. HTTP/0.9 over TLS is not
routed: wrapping `:443` after `tls` would hide the `*tls.Conn` from net/http and break
HTTP/2 for every site.

The server reads `/run/cluster-dashboard/agent.sock` (group 29925) and publishes an
allowlisted summary only: node names, CPU, memory, traffic, uptime, load and the names
of running containers. No addresses, images, mounts, kernel or revision.

## DNS (Cloudflare, done by the operator)

`oriom.dev` and `www.oriom.dev`: `A 133.18.180.180`, `AAAA 2406:8c00:0:3462:133:18:180:180`,
**DNS only** (grey cloud). The Cloudflare proxy would end HTTP/0.9, HTTP/1.0 without
TLS and CoAP at Cloudflare.

## Checks after deploy

```sh
printf 'GET /\r\n' | nc oriom.dev 80 | head -c 200      # HTTP/0.9
curl -0 -s http://oriom.dev/index.md | head              # HTTP/1.0 without TLS
curl --http3 -sI https://oriom.dev/                      # HTTP/3
coap-client -m get coap://oriom.dev/.well-known/core     # CoAP (libcoap)
```
