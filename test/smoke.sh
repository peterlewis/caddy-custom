#!/usr/bin/env bash
# Smoke test for a caddy-custom image. CI runs it before anything is pushed,
# because whatever lands on :latest goes live on a3239's internet-facing proxy.
#
# It runs the image the way a3239 does (`caddy docker-proxy`, the Docker socket,
# a base Caddyfile plus container labels) and checks what that setup depends on:
# the versions the Dockerfile asks for, label-driven reverse proxying, a
# caddy-security portal and policy, layer4 TCP proxying and the Cloudflare DNS
# provider. a3239's own Caddyfile isn't in this repo, so it can't be loaded here.
#
# Usage: test/smoke.sh <image>
set -euo pipefail

image=${1:?usage: $0 <image>}
cd "$(dirname "$0")/.."

run=caddy-smoke-$$
fail() {
	echo "FAIL: $*" >&2
	if docker container inspect "$run-caddy" >/dev/null 2>&1; then
		docker logs "$run-caddy" 2>&1 | tail -n 40 >&2
	fi
	exit 1
}
cleanup() {
	docker rm -f "$run-caddy" "$run-public" "$run-private" >/dev/null 2>&1 || true
	docker network rm "$run" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Throwaway secrets under the names a3239 uses.
secrets=(
	-e JWT_SHARED_KEY=smoke-test-shared-key-0123456789abcdef
	-e AZURE_CLIENT_SECRET=smoke-test-client-secret
	-e CLOUDFLARE_API_TOKEN=smoketest0token0000000000000000000000000
)

echo "== Versions"
runtime=$(sed -nE 's/^FROM caddy:([0-9.]+)@sha256:.*/\1/p' Dockerfile)
builder=$(sed -nE 's/^FROM .*caddy:([0-9.]+)-builder@sha256:.*/\1/p' Dockerfile)
[[ -n $runtime && $runtime == "$builder" ]] ||
	fail "Dockerfile's caddy images disagree (builder '$builder', runtime '$runtime')"
version=$(docker run --rm "$image" caddy version | cut -d' ' -f1)
[[ $version == "v$runtime" ]] || fail "caddy reports $version; the Dockerfile asks for $runtime"
echo "caddy $version"

# Each "# renovate: datasource=go depName=<module>" line sits above "ARG <NAME>=<version>".
buildinfo=$(docker run --rm "$image" caddy build-info)
plugins=$(awk '/^# renovate: datasource=go / {
	for (i = 1; i <= NF; i++) if ($i ~ /^depName=/) module = substr($i, 9)
	getline; split($2, arg, "="); print module, arg[2]
}' Dockerfile)
[[ -n $plugins ]] || fail "no plugin pins found in the Dockerfile"
while read -r module want; do
	have=$(awk -v m="$module" '$1 == "dep" && $2 == m { print $3 }' <<<"$buildinfo")
	[[ $have == "$want" ]] || fail "$module is ${have:-missing}; the Dockerfile asks for $want"
	echo "$module $have"
done <<<"$plugins"

echo "== Modules"
modules=$(docker run --rm "$image" caddy list-modules)
for module in docker_proxy security http.handlers.authenticator \
	http.authentication.providers.authorizer dns.providers.cloudflare layer4 layer4.handlers.proxy; do
	grep -qxF "$module" <<<"$modules" || fail "module $module is missing"
done
echo "all present"

echo "== Cloudflare DNS provider"
docker run --rm "${secrets[@]}" -v "$PWD/test/cloudflare.Caddyfile:/etc/caddy/Caddyfile:ro" "$image" \
	caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 ||
	fail "a site using 'dns cloudflare' did not validate"
echo "validates"

echo "== caddy docker-proxy"
docker network create "$run" >/dev/null
# Upstreams are started first so the proxy's first scan finds them.
upstream() {
	local name=$1
	shift
	docker run -d --name "$run-$name" --network "$run" --network-alias "$name" \
		--label "caddy=http://$name.smoke.test" \
		--label caddy.import=common_smoke \
		--label 'caddy.reverse_proxy={{upstreams 80}}' \
		"$@" "$image" caddy respond --listen :80 "hello from $name" >/dev/null
}
upstream public
upstream private --label 'caddy.authorize=with smokepolicy'

docker run -d --name "$run-caddy" --network "$run" --security-opt no-new-privileges:true \
	"${secrets[@]}" \
	-e CADDY_INGRESS_NETWORKS="$run" \
	-e CADDY_DOCKER_CADDYFILE_PATH=/etc/caddy/Caddyfile \
	-v "$PWD/test/Caddyfile:/etc/caddy/Caddyfile:ro" \
	-v /var/run/docker.sock:/var/run/docker.sock:ro \
	-p 127.0.0.1::80 -p 127.0.0.1::6667 \
	"$image" >/dev/null
http=$(docker port "$run-caddy" 80/tcp | head -n 1)
l4=$(docker port "$run-caddy" 6667/tcp | head -n 1)

# Every *.smoke.test name goes to the proxy's published HTTP port.
fetch() { curl -sS --max-time 5 --connect-to "::$http" "$@"; }

for _ in $(seq 30); do
	[[ $(fetch -f http://public.smoke.test/ 2>/dev/null) == "hello from public" ]] && break
	[[ $(docker inspect -f '{{.State.Running}}' "$run-caddy") == true ]] || fail "caddy exited"
	sleep 1
done
[[ $(fetch -f http://public.smoke.test/) == "hello from public" ]] || fail "labelled site never answered"
fetch -I http://public.smoke.test/ | grep -qi '^server:' && fail "the caddy.import label's snippet wasn't applied"
echo "labelled site proxies and imports its snippet"

read -r status location < <(fetch -o /dev/null -w '%{http_code} %{redirect_url}\n' \
	-H 'Accept: text/html' http://private.smoke.test/)
[[ $status == 30[23] && $location == http://auth.smoke.test/* ]] ||
	fail "protected site gave '$status $location', not a redirect to the portal"
fetch http://private.smoke.test/ | grep -q 'hello from private' && fail "protected site served its upstream without a login"
echo "authorize redirects to the portal"

portal=$(fetch -L http://auth.smoke.test/)
grep -qi azure <<<"$portal" || fail "portal page doesn't offer the Azure provider"
echo "portal offers Azure sign-in"

[[ $(curl -sS --max-time 5 "http://$l4/") == "hello from public" ]] || fail "layer4 didn't proxy TCP"
echo "layer4 proxies TCP"

if docker logs "$run-caddy" 2>&1 | grep -qE 'panic|nil pointer'; then
	fail "caddy logged a panic"
fi
echo "PASS"
