# Everything that goes into the image is pinned, so a rebuild of the same commit
# produces the same Caddy. Renovate (renovate.json5) moves the pins: the two
# caddy images as one update, the plugins via the "# renovate:" comments.
#
# The builder runs on the build machine's own architecture and cross-compiles,
# so the arm64 image needs no emulation.
FROM --platform=$BUILDPLATFORM caddy:2.11.8-builder@sha256:212168c3a069fb6a18ced9e817f974c8a5ef21a41d305bcdb66ec0bd416079ef AS builder

# renovate: datasource=go depName=github.com/lucaslorentz/caddy-docker-proxy/v2
ARG CADDY_DOCKER_PROXY_VERSION=v2.13.1
# renovate: datasource=go depName=github.com/greenpau/caddy-security
ARG CADDY_SECURITY_VERSION=v1.1.64
# renovate: datasource=go depName=github.com/caddy-dns/cloudflare
ARG CADDY_DNS_CLOUDFLARE_VERSION=v0.2.4
# renovate: datasource=go depName=github.com/mholt/caddy-l4
ARG CADDY_L4_VERSION=v0.1.2

ARG TARGETOS TARGETARCH TARGETVARIANT
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOOS=$TARGETOS GOARCH=$TARGETARCH GOARM=${TARGETVARIANT#v} CGO_ENABLED=0 \
    xcaddy build \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@${CADDY_DOCKER_PROXY_VERSION} \
    --with github.com/greenpau/caddy-security@${CADDY_SECURITY_VERSION} \
    --with github.com/caddy-dns/cloudflare@${CADDY_DNS_CLOUDFLARE_VERSION} \
    --with github.com/mholt/caddy-l4@${CADDY_L4_VERSION}

FROM caddy:2.11.8@sha256:f04f1e8d78da0c65ec6f81b4ea8d216849775f3bc3c87790d95fcb2ec3722f12
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
CMD ["caddy", "docker-proxy"]
