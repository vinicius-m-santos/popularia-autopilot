#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image="popularia-autopilot:smoke"
container=''
volume=''

cleanup() {
  [[ -n "${container}" ]] && docker rm -f "${container}" >/dev/null 2>&1 || true
  [[ -n "${volume}" ]] && docker volume rm "${volume}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build --tag "${image}" "${repo_root}"
volume="popularia-autopilot-smoke-$RANDOM-$RANDOM"
docker volume create "${volume}" >/dev/null
container="$(docker run --detach --publish-all \
  --env PORT=8080 \
  --env CEZ_DRY_RUN=1 \
  --env DASHBOARD_USERNAME=smoke \
  --env DASHBOARD_PASSWORD=smoke-only-password-123456789 \
  --mount "type=volume,source=${volume},target=/data" \
  "${image}")"

host_port=''
for _ in $(seq 1 90); do
  host_port="$(docker port "${container}" 8080/tcp 2>/dev/null | sed -n 's/.*://p' | head -1)"
  if [[ -n "${host_port}" ]] && curl --fail --silent "http://127.0.0.1:${host_port}/healthz" >/dev/null; then
    break
  fi
  if [[ "$(docker inspect --format '{{.State.Running}}' "${container}")" != true ]]; then
    docker logs "${container}" >&2
    exit 1
  fi
  sleep 1
done

[[ -n "${host_port}" ]]
curl --fail --silent "http://127.0.0.1:${host_port}/healthz" >/dev/null

unauthenticated_status="$(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:${host_port}/")"
[[ "${unauthenticated_status}" == 401 ]]

authenticated_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --user 'smoke:smoke-only-password-123456789' "http://127.0.0.1:${host_port}/")"
[[ "${authenticated_status}" == 200 ]]

workflows="$(curl --fail --silent \
  --user 'smoke:smoke-only-password-123456789' "http://127.0.0.1:${host_port}/api/v1/workflows")"
grep -q 'claude-plan-opencode' <<<"${workflows}"
grep -q 'codex-plan-opencode' <<<"${workflows}"

docker exec "${container}" test -f /data/cezar/config.json
docker exec "${container}" grep -q '"maxParallel": 2' /data/cezar/config.json
docker exec "${container}" test -d /data/workspaces/popularia-control/.git

echo 'docker smoke test passed'
