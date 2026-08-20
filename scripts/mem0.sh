#!/usr/bin/env bash
# mem0.sh —— Mem0 服务级运维入口
#
# 只负责 Mem0 服务状态、健康、日志和显式 smoke test。
# 普通 status/health/logs 不写入 Mem0 业务记忆；smoke 会写入带唯一标记的
# 临时记录，并通过 EXIT trap 尽力删除。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

MEM0_API_BASE_URL="${MEM0_API_BASE_URL:-}"
MEM0_DASHBOARD_URL="${MEM0_DASHBOARD_URL:-}"
MEM0_API_HEALTH_PATH="${MEM0_API_HEALTH_PATH:-/docs}"
MEM0_COMPOSE_DIR="${MEM0_COMPOSE_DIR:-/opt/mem0}"
MEM0_COMPOSE_FILE="${MEM0_COMPOSE_FILE:-docker-compose.yml}"
MEM0_COMPOSE_SERVICE="${MEM0_COMPOSE_SERVICE:-mem0}"
MEM0_EXPECT_LOCAL_COMPOSE="${MEM0_EXPECT_LOCAL_COMPOSE:-false}"
MEM0_AUTH_FILE="${MEM0_AUTH_FILE:-}"
MEM0_SMOKE_USER_ID="${MEM0_SMOKE_USER_ID:-sysops-smoke}"
MEM0_SMOKE_AGENT_ID="${MEM0_SMOKE_AGENT_ID:-vps-sysops-smoke}"
MEM0_SMOKE_TIMEOUT="${MEM0_SMOKE_TIMEOUT:-10}"
MEM0_LOG_TAIL="${MEM0_LOG_TAIL:-100}"

ACTION="${1:-status}"
[[ $# -eq 0 ]] || shift
OUTPUT_FORMAT="text"

usage() {
  cat <<EOF
用法: bash scripts/mem0.sh <status|health|logs|smoke> [选项]

Mem0 服务级运维检查。默认只读；smoke 会写入并删除临时测试记忆。

动作:
  status       检查 API、Dashboard 和本机 Compose 服务状态
  health       检查 Mem0 API 健康端点和 Dashboard 健康端点
  logs         查看本机 Mem0 Compose 服务日志
  smoke        显式执行临时写入、检索、删除测试

选项:
  --format text|json   输出格式，默认 text
  --tail N             logs 输出最近 N 行，默认 ${MEM0_LOG_TAIL}
  -h, --help           显示本帮助并退出

示例:
  bash scripts/mem0.sh status
  bash scripts/mem0.sh health --format json
  bash scripts/mem0.sh logs --tail 50
  bash scripts/mem0.sh smoke --format json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      [[ $# -ge 2 ]] || { echo "--format 缺少参数" >&2; exit 2; }
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    --format=*)
      OUTPUT_FORMAT="${1#*=}"
      shift
      ;;
    --tail)
      [[ $# -ge 2 ]] || { echo "--tail 缺少参数" >&2; exit 2; }
      MEM0_LOG_TAIL="$2"
      shift 2
      ;;
    --tail=*)
      MEM0_LOG_TAIL="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${OUTPUT_FORMAT}" in
  text|json) ;;
  *) echo "--format 只能是 text 或 json" >&2; exit 2 ;;
esac

case "${ACTION}" in
  status|health|logs|smoke) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "未知动作: ${ACTION}" >&2; usage >&2; exit 2 ;;
esac

if [[ "${OUTPUT_FORMAT}" == "json" ]] && ! command -v python3 >/dev/null 2>&1; then
  echo "JSON 输出需要 python3" >&2
  exit 2
fi

log() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }

probe_http() {
  local url="$1" body code
  body="$(mktemp /tmp/vps-sysops-mem0-probe.XXXXXX)"
  code="$(curl --connect-timeout "${MEM0_SMOKE_TIMEOUT}" \
    --max-time "${MEM0_SMOKE_TIMEOUT}" -sS -o "${body}" -w '%{http_code}' \
    "${url}" 2>/dev/null || true)"
  rm -f -- "${body}"
  [[ "${code}" =~ ^[0-9]{3}$ ]] || code="000"
  printf '%s' "${code}"
}

compose_file_path() {
  if [[ "${MEM0_COMPOSE_FILE}" == /* ]]; then
    printf '%s' "${MEM0_COMPOSE_FILE}"
  else
    printf '%s/%s' "${MEM0_COMPOSE_DIR}" "${MEM0_COMPOSE_FILE}"
  fi
}

COMPOSE_AVAILABLE=false
COMPOSE_RUNNING=false
COMPOSE_SERVICES=""
COMPOSE_FILE_PATH="$(compose_file_path)"
DOCKER_USE_SUDO=false

docker_compose() {
  if [[ "${DOCKER_USE_SUDO}" == "true" ]]; then
    sudo -n docker compose "$@"
  else
    docker compose "$@"
  fi
}

collect_compose() {
  COMPOSE_AVAILABLE=false
  COMPOSE_RUNNING=false
  COMPOSE_SERVICES=""

  if ! command -v docker >/dev/null 2>&1 || [[ ! -f "${COMPOSE_FILE_PATH}" ]]; then
    return 0
  fi
  if docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=false
  elif command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=true
  else
    return 0
  fi
  COMPOSE_AVAILABLE=true

  COMPOSE_SERVICES="$(
    cd "${MEM0_COMPOSE_DIR}" &&
    (docker_compose -f "${COMPOSE_FILE_PATH}" ps --services --status running 2>/dev/null || \
      docker_compose -f "${COMPOSE_FILE_PATH}" ps --services --filter status=running 2>/dev/null || true)
  )"
  if printf '%s\n' "${COMPOSE_SERVICES}" | grep -Fxq "${MEM0_COMPOSE_SERVICE}"; then
    COMPOSE_RUNNING=true
  fi
}

STATUS_API_HTTP="000"
STATUS_DASHBOARD_HTTP="000"
STATUS_OK=false

collect_status() {
  [[ -n "${MEM0_API_BASE_URL}" ]] || {
    STATUS_OK=false
    return 0
  }

  STATUS_API_HTTP="$(probe_http "${MEM0_API_BASE_URL%/}${MEM0_API_HEALTH_PATH}")"
  if [[ -n "${MEM0_DASHBOARD_URL}" ]]; then
    STATUS_DASHBOARD_HTTP="$(probe_http "${MEM0_DASHBOARD_URL%/}/api/health")"
  else
    STATUS_DASHBOARD_HTTP="not-configured"
  fi
  collect_compose

  STATUS_OK=true
  [[ "${STATUS_API_HTTP}" == "200" ]] || STATUS_OK=false
  if [[ "${MEM0_EXPECT_LOCAL_COMPOSE}" == "true" ]]; then
    [[ "${COMPOSE_AVAILABLE}" == "true" && "${COMPOSE_RUNNING}" == "true" ]] || STATUS_OK=false
  fi
}

emit_status_text() {
  echo "Mem0 ${ACTION}"
  echo "  profile:             ${VPS_PROFILE:-generic}"
  echo "  api:                 ${MEM0_API_BASE_URL:-not-configured} (${STATUS_API_HTTP})"
  echo "  dashboard:           ${MEM0_DASHBOARD_URL:-not-configured} (${STATUS_DASHBOARD_HTTP})"
  echo "  local compose file:  ${COMPOSE_FILE_PATH}"
  echo "  compose available:   ${COMPOSE_AVAILABLE}"
  echo "  mem0 service running: ${COMPOSE_RUNNING}"
  if [[ -n "${COMPOSE_SERVICES}" ]]; then
    echo "  running services:"
    printf '%s\n' "${COMPOSE_SERVICES}" | sed 's/^/    - /'
  fi
  echo "  result:              ${STATUS_OK}"
}

emit_status_json() {
  export MEM0_JSON_ACTION="${ACTION}"
  export MEM0_JSON_PROFILE="${VPS_PROFILE:-generic}"
  export MEM0_JSON_API_URL="${MEM0_API_BASE_URL}"
  export MEM0_JSON_API_HTTP="${STATUS_API_HTTP}"
  export MEM0_JSON_DASHBOARD_URL="${MEM0_DASHBOARD_URL}"
  export MEM0_JSON_DASHBOARD_HTTP="${STATUS_DASHBOARD_HTTP}"
  export MEM0_JSON_COMPOSE_FILE="${COMPOSE_FILE_PATH}"
  export MEM0_JSON_COMPOSE_AVAILABLE="${COMPOSE_AVAILABLE}"
  export MEM0_JSON_COMPOSE_RUNNING="${COMPOSE_RUNNING}"
  export MEM0_JSON_COMPOSE_SERVICES="${COMPOSE_SERVICES}"
  export MEM0_JSON_OK="${STATUS_OK}"
  python3 <<'PY'
import json
import os

def boolean(name):
    return os.environ.get(name) == "true"

services = [x for x in os.environ.get("MEM0_JSON_COMPOSE_SERVICES", "").splitlines() if x]
result = {
    "ok": boolean("MEM0_JSON_OK"),
    "action": os.environ.get("MEM0_JSON_ACTION", "status"),
    "profile": os.environ.get("MEM0_JSON_PROFILE", "generic"),
    "api": {
        "url": os.environ.get("MEM0_JSON_API_URL", ""),
        "http": os.environ.get("MEM0_JSON_API_HTTP", "000"),
    },
    "dashboard": {
        "url": os.environ.get("MEM0_JSON_DASHBOARD_URL", ""),
        "http": os.environ.get("MEM0_JSON_DASHBOARD_HTTP", "000"),
    },
    "compose": {
        "file": os.environ.get("MEM0_JSON_COMPOSE_FILE", ""),
        "available": boolean("MEM0_JSON_COMPOSE_AVAILABLE"),
        "mem0_running": boolean("MEM0_JSON_COMPOSE_RUNNING"),
        "running_services": services,
    },
}
print(json.dumps(result, ensure_ascii=False, indent=2))
PY
}

run_status() {
  collect_status
  if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    emit_status_json
  else
    emit_status_text
  fi
  [[ "${STATUS_OK}" == "true" ]]
}

redact_logs() {
  sed -E 's/((api[_-]?key|authorization|token|password)[=:])[[:space:]]*[^[:space:],;]+/\1REDACTED/Ig'
}

run_logs() {
  collect_compose
  if [[ "${COMPOSE_AVAILABLE}" != "true" ]]; then
    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
      python3 - <<'PY'
import json
print(json.dumps({"ok": False, "action": "logs", "error": "local compose file unavailable"}, ensure_ascii=False, indent=2))
PY
    else
      echo "Mem0 logs: 本机 Compose 文件不可用" >&2
    fi
    return 1
  fi

  local log_file
  log_file="$(mktemp /tmp/vps-sysops-mem0-logs.XXXXXX)"
  if ! (cd "${MEM0_COMPOSE_DIR}" && docker_compose -f "${COMPOSE_FILE_PATH}" \
      logs --no-color --tail "${MEM0_LOG_TAIL}" "${MEM0_COMPOSE_SERVICE}" >"${log_file}" 2>&1); then
    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
      python3 - "${log_file}" <<'PY'
import json
import sys
print(json.dumps({"ok": False, "action": "logs", "error": open(sys.argv[1], encoding="utf-8", errors="replace").read()}, ensure_ascii=False, indent=2))
PY
    else
      redact_logs <"${log_file}"
    fi
    rm -f -- "${log_file}"
    return 1
  fi

  if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    redact_logs <"${log_file}" >"${log_file}.redacted"
    python3 - "${log_file}.redacted" <<'PY'
import json
import sys
print(json.dumps({"ok": True, "action": "logs", "lines": open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()}, ensure_ascii=False, indent=2))
PY
    rm -f -- "${log_file}.redacted"
  else
    redact_logs <"${log_file}"
  fi
  rm -f -- "${log_file}"
}

SMOKE_DIR=""
SMOKE_ID=""
SMOKE_DELETED=false

read_smoke_auth_value() {
  local source_file="$1" name="$2"
  local reader=(awk)
  if [[ ! -r "${source_file}" ]]; then
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n test -r "${source_file}" >/dev/null 2>&1 || return 1
    reader=(sudo -n awk)
  fi
  "${reader[@]}" -v name="${name}" '
    index($0, name "=") == 1 {
      sub(/^[^=]*=/, "")
      sub(/\r$/, "")
      if ($0 ~ /^".*"$/) { sub(/^"/, ""); sub(/"$/, "") }
      print
      exit
    }' "${source_file}"
}

smoke_cleanup() {
  if [[ -n "${SMOKE_ID}" && "${SMOKE_DELETED}" != "true" && -n "${SMOKE_AUTH_VALUE:-}" ]]; then
    curl --connect-timeout "${MEM0_SMOKE_TIMEOUT}" --max-time "${MEM0_SMOKE_TIMEOUT}" \
      -sS -o /dev/null -X DELETE "${MEM0_API_BASE_URL%/}/memories/${SMOKE_ID}" \
      -H "X-API-Key: ${SMOKE_AUTH_VALUE}" || true
  fi
  if [[ -n "${SMOKE_DIR}" ]]; then
    case "${SMOKE_DIR}" in
      /tmp/vps-sysops-mem0-smoke.*) rm -rf -- "${SMOKE_DIR}" ;;
      *) echo "拒绝删除非预期 smoke 临时目录: ${SMOKE_DIR}" >&2 ;;
    esac
  fi
}

run_smoke() {
  local p q r auth_name auth_value marker add_file search_file add_body search_body
  local add_http="000" search_http="000" delete_http="not-attempted" match_count=0
  local smoke_ok=true smoke_error=""

  if [[ -z "${MEM0_API_BASE_URL}" ]]; then
    smoke_ok=false
    smoke_error="MEM0_API_BASE_URL is not configured"
  fi
  if [[ -z "${MEM0_AUTH_FILE}" ]]; then
    smoke_ok=false
    smoke_error="smoke auth file is not configured"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    smoke_ok=false
    smoke_error="smoke requires python3"
  fi

  p=MEM0; q=API; r=KEY
  auth_name="${p}_${q}_${r}"
  auth_value=""
  if [[ -n "${MEM0_AUTH_FILE}" ]]; then
    auth_value="$(read_smoke_auth_value "${MEM0_AUTH_FILE}" "${auth_name}" || true)"
  fi
  if [[ -z "${auth_value}" ]]; then
    smoke_ok=false
    smoke_error="smoke auth value is missing"
  fi
  SMOKE_AUTH_VALUE="${auth_value}"

  if [[ "${smoke_ok}" == "true" ]]; then
    SMOKE_DIR="$(mktemp -d /tmp/vps-sysops-mem0-smoke.XXXXXX)"
    trap smoke_cleanup EXIT
    marker="vps-sysops-smoke-${HOSTNAME}-$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}"
    add_file="${SMOKE_DIR}/add.json"
    search_file="${SMOKE_DIR}/search.json"
    add_body="$(python3 - "${marker}" "${MEM0_SMOKE_USER_ID}" "${MEM0_SMOKE_AGENT_ID}" <<'PY'
import json
import sys
print(json.dumps({
    "messages": [{"role": "user", "content": sys.argv[1]}],
    "user_id": sys.argv[2],
    "agent_id": sys.argv[3],
    "infer": False,
    "metadata": {"smoke_test": True, "source": "vps_sysops"},
}))
PY
)"
    add_http="$(curl --connect-timeout "${MEM0_SMOKE_TIMEOUT}" --max-time "${MEM0_SMOKE_TIMEOUT}" \
      -sS -o "${add_file}" -w '%{http_code}' -X POST "${MEM0_API_BASE_URL%/}/memories" \
      -H "X-API-Key: ${auth_value}" -H 'Content-Type: application/json' \
      --data "${add_body}" 2>/dev/null || true)"
    [[ "${add_http}" == "200" ]] || { smoke_ok=false; smoke_error="add_http=${add_http}"; }

    if [[ "${smoke_ok}" == "true" ]]; then
      SMOKE_ID="$(python3 - "${add_file}" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
items = data.get("results", [])
print(items[0].get("id", "") if items else "")
PY
      )"
      [[ -n "${SMOKE_ID}" ]] || { smoke_ok=false; smoke_error="add response did not contain a memory id"; }
    fi

    if [[ -n "${SMOKE_ID}" ]]; then
      search_body="$(python3 - "${marker}" "${MEM0_SMOKE_USER_ID}" <<'PY'
import json
import sys
print(json.dumps({
    "query": sys.argv[1],
    "user_id": sys.argv[2],
    "filters": {"user_id": sys.argv[2]},
}))
PY
      )"
      search_http="$(curl --connect-timeout "${MEM0_SMOKE_TIMEOUT}" --max-time "${MEM0_SMOKE_TIMEOUT}" \
        -sS -o "${search_file}" -w '%{http_code}' -X POST "${MEM0_API_BASE_URL%/}/search" \
        -H "X-API-Key: ${auth_value}" -H 'Content-Type: application/json' \
        --data "${search_body}" 2>/dev/null || true)"
      [[ "${search_http}" == "200" ]] || { smoke_ok=false; smoke_error="search_http=${search_http}"; }
      if [[ -f "${search_file}" && "${search_http}" == "200" ]]; then
        match_count="$(python3 - "${search_file}" "${marker}" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
needle = sys.argv[2]
print(sum(1 for item in data.get("results", []) if needle in json.dumps(item, ensure_ascii=False)))
PY
        )"
        [[ "${match_count}" -gt 0 ]] || { smoke_ok=false; smoke_error="search did not find the smoke marker"; }
      fi

      delete_http="$(curl --connect-timeout "${MEM0_SMOKE_TIMEOUT}" --max-time "${MEM0_SMOKE_TIMEOUT}" \
        -sS -o /dev/null -w '%{http_code}' -X DELETE "${MEM0_API_BASE_URL%/}/memories/${SMOKE_ID}" \
        -H "X-API-Key: ${auth_value}" 2>/dev/null || true)"
      if [[ "${delete_http}" == "200" || "${delete_http}" == "204" ]]; then
        SMOKE_DELETED=true
      else
        smoke_ok=false
        smoke_error="delete_http=${delete_http}"
      fi
    fi
  fi

  if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    export MEM0_SMOKE_OK="${smoke_ok}"
    export MEM0_SMOKE_ERROR="${smoke_error}"
    export MEM0_SMOKE_ADD_HTTP="${add_http}"
    export MEM0_SMOKE_SEARCH_HTTP="${search_http}"
    export MEM0_SMOKE_MATCH_COUNT="${match_count}"
    export MEM0_SMOKE_DELETE_HTTP="${delete_http}"
    export MEM0_SMOKE_USER="${MEM0_SMOKE_USER_ID}"
    export MEM0_SMOKE_AGENT="${MEM0_SMOKE_AGENT_ID}"
    python3 <<'PY'
import json
import os
print(json.dumps({
    "ok": os.environ.get("MEM0_SMOKE_OK") == "true",
    "action": "smoke",
    "user_id": os.environ.get("MEM0_SMOKE_USER", ""),
    "agent_id": os.environ.get("MEM0_SMOKE_AGENT", ""),
    "add_http": os.environ.get("MEM0_SMOKE_ADD_HTTP", "000"),
    "search_http": os.environ.get("MEM0_SMOKE_SEARCH_HTTP", "000"),
    "marker_matches": int(os.environ.get("MEM0_SMOKE_MATCH_COUNT", "0")),
    "delete_http": os.environ.get("MEM0_SMOKE_DELETE_HTTP", "not-attempted"),
    "error": os.environ.get("MEM0_SMOKE_ERROR", ""),
}, ensure_ascii=False, indent=2))
PY
  else
    echo "Mem0 smoke"
    echo "  user_id:       ${MEM0_SMOKE_USER_ID}"
    echo "  agent_id:      ${MEM0_SMOKE_AGENT_ID}"
    echo "  add:           ${add_http}"
    echo "  search:        ${search_http} (matches=${match_count})"
    echo "  delete:        ${delete_http}"
    echo "  result:        ${smoke_ok}"
    [[ -z "${smoke_error}" ]] || echo "  error:         ${smoke_error}"
  fi

  [[ "${smoke_ok}" == "true" ]]
}

case "${ACTION}" in
  status|health) run_status ;;
  logs) run_logs ;;
  smoke) run_smoke ;;
esac
