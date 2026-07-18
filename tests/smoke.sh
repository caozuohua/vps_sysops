#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while IFS= read -r -d '' script; do
  bash -n "${script}"
done < <(find "${ROOT_DIR}/scripts" -maxdepth 1 -type f -name '*.sh' -print0)
bash -n "${ROOT_DIR}/ops.sh" "${ROOT_DIR}/config/ops.conf" \
  "${ROOT_DIR}/config/hosts/gcp.conf" "${ROOT_DIR}/config/hosts/azure.conf"

VPS_PROFILE=gcp bash -c '
  source "$1/config/ops.conf"
  [[ "$VPS_PROFILE" == gcp ]]
  [[ "$PUBLIC_IP" == 35.212.145.19 ]]
  [[ "$TAILSCALE_IP" == 100.101.90.114 ]]
  [[ "$MONITOR_SERVICES" == *new-api* ]]
  [[ "$SQLITE_DATABASES" == *one-api.db* ]]
' _ "${ROOT_DIR}"

VPS_PROFILE=azure bash -c '
  source "$1/config/ops.conf"
  [[ "$VPS_PROFILE" == azure ]]
  [[ "$PUBLIC_IP" == 52.225.28.230 ]]
  [[ "$TAILSCALE_IP" == 100.87.159.14 ]]
  [[ "$MONITOR_USER" == caozuohua ]]
  [[ "$TAILSCALE_DENY_TARGETS" == *100.101.90.114:50404* ]]
' _ "${ROOT_DIR}"

grep -q '"desktop": "100.124.35.84"' "${ROOT_DIR}/system/tailscale/grants.hujson"
grep -q '"azure":   "100.87.159.14"' "${ROOT_DIR}/system/tailscale/grants.hujson"

if command -v python3 >/dev/null 2>&1; then
  ROOT_DIR="${ROOT_DIR}" python3 - <<'PY'
import ast
import os
from pathlib import Path

for path in (Path(os.environ["ROOT_DIR"]) / "a2a-bridge").glob("*.py"):
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY
fi

echo "smoke tests passed"
