FROM caddy:2.11.4-builder AS builder
RUN xcaddy build \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2 \
    --with github.com/greenpau/caddy-security@v1.1.62 \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/mholt/caddy-l4@v0.1.0

FROM caddy:2.11.4
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
CMD ["caddy", "docker-proxy"]
