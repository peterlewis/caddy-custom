# caddy-custom

The official Caddy image rebuilt with [caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy), [caddy-security](https://github.com/greenpau/caddy-security), the [Cloudflare DNS provider](https://github.com/caddy-dns/cloudflare) and [layer4](https://github.com/mholt/caddy-l4). It runs as the reverse proxy on a3239, from `caddy/docker-compose.yml` in portainer-compose.

## Tags

`ghcr.io/peterlewis/caddy-custom` is published for amd64 and arm64 as:

- the Caddy version, e.g. `2.11.8`, which moves when a plugin or base image is updated;
- `latest`;
- the full commit SHA, which never moves.

## How it stays current

Every version that goes into the image is pinned in the `Dockerfile`. Renovate (`renovate.json5`, run by `.github/workflows/renovate.yml`) moves those pins once a release is a week old. Each change is built for both architectures and put through `test/smoke.sh`, which runs the image as a3239 does and checks the portal and policy, label-driven proxying, layer4 and the Cloudflare provider. Patches, digest refreshes and most minors then merge themselves, and a merge to `main` publishes. New Caddy minors, pre-1.0 plugin minors and caddy-security minors wait for a hand merge.

A weekly build also checks that everything still builds, and stops GitHub switching the schedules off after 60 quiet days.

Renovate needs a `RENOVATE_TOKEN` secret; the comment at the top of its workflow says which permissions. Until it exists, the Renovate runs fail.

## Rolling back

Point the compose file at the previous image's commit-SHA tag, e.g. `ghcr.io/peterlewis/caddy-custom:<sha>`, then revert the offending commit here.
