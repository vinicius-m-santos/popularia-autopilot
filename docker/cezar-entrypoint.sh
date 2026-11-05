#!/usr/bin/env bash
set -Eeuo pipefail

readonly PUBLIC_PORT="${PORT:-8080}"
readonly INTERNAL_PORT="${CEZ_INTERNAL_PORT:-4321}"
readonly DATA_ROOT="/data"
readonly WORKSPACES_ROOT="${CEZ_PROJECTS_DIR:-/data/workspaces}"
readonly CONTROL_REPO="${WORKSPACES_ROOT}/popularia-control"
readonly CEZAR_CONFIG="${CEZ_HOME:-/data/cezar}/config.json"
readonly DASHBOARD_USER_VALUE="${DASHBOARD_USERNAME:-}"
readonly DASHBOARD_PASSWORD_VALUE="${DASHBOARD_PASSWORD:-}"

if [[ ! "${PUBLIC_PORT}" =~ ^[0-9]+$ ]] || (( PUBLIC_PORT < 1024 || PUBLIC_PORT > 65535 )); then
  echo "[entrypoint] PORT must be an integer between 1024 and 65535" >&2
  exit 1
fi

if [[ ! "${INTERNAL_PORT}" =~ ^[0-9]+$ ]] || (( INTERNAL_PORT < 1024 || INTERNAL_PORT > 65535 )); then
  echo "[entrypoint] CEZ_INTERNAL_PORT must be an integer between 1024 and 65535" >&2
  exit 1
fi

if [[ "${PUBLIC_PORT}" == "${INTERNAL_PORT}" ]]; then
  echo "[entrypoint] PORT and CEZ_INTERNAL_PORT must be different" >&2
  exit 1
fi

if [[ -z "${DASHBOARD_USER_VALUE}" || ! "${DASHBOARD_USER_VALUE}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "[entrypoint] DASHBOARD_USERNAME is required and may contain only letters, numbers, dot, underscore and hyphen" >&2
  exit 1
fi

if (( ${#DASHBOARD_PASSWORD_VALUE} < 16 )); then
  echo "[entrypoint] DASHBOARD_PASSWORD is required and must contain at least 16 characters" >&2
  exit 1
fi

mkdir -p \
  "${DATA_ROOT}/home/.config" \
  "${DATA_ROOT}/home/.local/share" \
  "${CEZ_HOME:-/data/cezar}" \
  "${WORKSPACES_ROOT}" \
  "${CONTROL_REPO}" \
  /run/cezar \
  /tmp/nginx/{client_body,proxy,fastcgi,uwsgi,scgi}
chown -R cezar:cezar "${DATA_ROOT}" /run/cezar /tmp/nginx

# Railway replaces the container PID namespace on deploy. Any owner.lock left by
# the previous container is therefore an ephemeral stale lease, not user data.
# Remove only cockpit lease files; keep config, credentials, runs and workspaces.
if [[ -d "${CEZ_HOME:-/data/cezar}/runtime/cockpits" ]]; then
  find "${CEZ_HOME:-/data/cezar}/runtime/cockpits" -mindepth 2 -maxdepth 2 \
    -type f -name 'owner.lock' -delete
fi

if [[ ! -f "${CEZAR_CONFIG}" ]]; then
  install -o cezar -g cezar -m 0600 /opt/popularia-bootstrap-config.json "${CEZAR_CONFIG}"
fi

# This repository is deployment-owned and exists only to give the cockpit a
# stable Git boot project. Application repositories are cloned alongside it.
cp -a /opt/popularia-bootstrap/. "${CONTROL_REPO}/"
chown -R cezar:cezar "${CONTROL_REPO}"
if [[ ! -d "${CONTROL_REPO}/.git" ]]; then
  gosu cezar git -C "${CONTROL_REPO}" init --initial-branch=main >/dev/null
  gosu cezar git -C "${CONTROL_REPO}" config user.name "Popularia Autopilot"
  gosu cezar git -C "${CONTROL_REPO}" config user.email "autopilot@localhost"
fi
gosu cezar git -C "${CONTROL_REPO}" add .
if ! gosu cezar git -C "${CONTROL_REPO}" diff --cached --quiet; then
  gosu cezar git -C "${CONTROL_REPO}" commit -m "chore: sync managed Cezar workflows" >/dev/null
fi

printf '%s\n' "${DASHBOARD_PASSWORD_VALUE}" \
  | htpasswd -i -c -B /run/cezar/.htpasswd "${DASHBOARD_USER_VALUE}" >/dev/null 2>&1
chown root:cezar /run/cezar/.htpasswd
chmod 0640 /run/cezar/.htpasswd

sed \
  -e "s/__PUBLIC_PORT__/${PUBLIC_PORT}/g" \
  -e "s/__CEZAR_INTERNAL_PORT__/${INTERNAL_PORT}/g" \
  /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -t

cezar_pid=''
nginx_pid=''

shutdown() {
  local signal="${1:-TERM}"
  [[ -n "${nginx_pid}" ]] && kill -s "${signal}" "${nginx_pid}" 2>/dev/null || true
  [[ -n "${cezar_pid}" ]] && kill -s "${signal}" "${cezar_pid}" 2>/dev/null || true
}
trap 'shutdown TERM' TERM INT

gosu cezar cezar-run serve \
  --repo "${CONTROL_REPO}" \
  --no-open \
  --port "${INTERNAL_PORT}" &
cezar_pid=$!

for _ in $(seq 1 60); do
  if ! kill -0 "${cezar_pid}" 2>/dev/null; then
    wait "${cezar_pid}"
    exit $?
  fi
  if curl --fail --silent "http://127.0.0.1:${INTERNAL_PORT}/api/v1/health" >/dev/null; then
    break
  fi
  sleep 1
done

if ! curl --fail --silent "http://127.0.0.1:${INTERNAL_PORT}/api/v1/health" >/dev/null; then
  echo "[entrypoint] Cezar did not become healthy within 60 seconds" >&2
  shutdown TERM
  wait "${cezar_pid}" || true
  exit 1
fi

nginx -g 'daemon off;' &
nginx_pid=$!

set +e
wait -n "${cezar_pid}" "${nginx_pid}"
status=$?
set -e
shutdown TERM
wait "${cezar_pid}" 2>/dev/null || true
wait "${nginx_pid}" 2>/dev/null || true
exit "${status}"
