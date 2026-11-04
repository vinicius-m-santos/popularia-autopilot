#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

required=(
  Dockerfile
  .railway/railway.ts
  docker/cezar-entrypoint.sh
  docker/nginx.conf.template
  config/workspace-config.json
  .ai/cezar/config.json
  .ai/cezar/workflows/claude-plan-opencode.yml
  .ai/cezar/workflows/codex-plan-opencode.yml
)

for path in "${required[@]}"; do
  [[ -s "${path}" ]] || { echo "missing or empty: ${path}" >&2; exit 1; }
done

bash -n docker/cezar-entrypoint.sh scripts/smoke-test.sh
node -e 'JSON.parse(require("fs").readFileSync("config/workspace-config.json", "utf8")); JSON.parse(require("fs").readFileSync(".ai/cezar/config.json", "utf8"));'

grep -q '"maxParallel": 2' config/workspace-config.json
grep -q 'CEZ_AUTOMATIONS=0' Dockerfile
grep -q 'CEZ_REVIEW_GATE=1' Dockerfile
grep -q 'auth_basic' docker/nginx.conf.template
grep -q 'git diff --check' .ai/cezar/workflows/claude-plan-opencode.yml
grep -q 'git diff --check' .ai/cezar/workflows/codex-plan-opencode.yml
grep -q 'builder: "DOCKERFILE"' .railway/railway.ts
grep -q 'volumeMounts: { "/data": cezarData }' .railway/railway.ts

if rg -n '(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,})' \
  --glob '!README.md' --glob '!.env.example' .; then
  echo 'possible credential found in tracked configuration' >&2
  exit 1
fi

echo 'static validation passed'
