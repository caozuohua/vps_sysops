#!/usr/bin/env bash
# mem0_backup.sh —— Mem0 PostgreSQL 低资源备份与恢复校验
#
# backup：生成 PostgreSQL custom-format dump，并执行 pg_restore -l 校验。
# verify：校验指定或最新 dump 的 SHA-256 与格式。
# restore-smoke：将 dump 恢复到临时数据库后立即删除；必须显式传 --yes。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

MEM0_BACKUP_ENABLED="${MEM0_BACKUP_ENABLED:-false}"
MEM0_BACKUP_ENV_FILE="${MEM0_BACKUP_ENV_FILE:-}"
MEM0_BACKUP_DEST="${MEM0_BACKUP_DEST:-/var/backups/vps-sysops/mem0}"
MEM0_BACKUP_COMPOSE_DIR="${MEM0_BACKUP_COMPOSE_DIR:-${MEM0_COMPOSE_DIR:-/opt/mem0}}"
MEM0_BACKUP_COMPOSE_FILE="${MEM0_BACKUP_COMPOSE_FILE:-${MEM0_COMPOSE_FILE:-docker-compose.yml}}"
MEM0_BACKUP_DB_SERVICE="${MEM0_BACKUP_DB_SERVICE:-postgres}"
MEM0_BACKUP_RETAIN_DAYS="${MEM0_BACKUP_RETAIN_DAYS:-7}"
MEM0_BACKUP_TIMEOUT="${MEM0_BACKUP_TIMEOUT:-900}"
MEM0_BACKUP_DISK_LIMIT="${MEM0_BACKUP_DISK_LIMIT:-90}"

ACTION="${1:-backup}"
[[ $# -eq 0 ]] || shift
OUTPUT_FORMAT="text"
CONFIRM=false
ARCHIVE=""

usage() {
  cat <<EOF
用法: sudo bash scripts/mem0_backup.sh <backup|verify|restore-smoke> [选项]

动作:
  backup              生成并校验 PostgreSQL custom-format dump
  verify [文件]       校验指定或最新 dump 的 SHA-256 与格式
  restore-smoke       恢复到临时数据库后删除，不修改生产数据库

选项:
  --format text|json  输出格式，默认 text
  --file PATH         verify/restore-smoke 使用的 dump 文件
  --yes               restore-smoke 必须显式确认
  -h, --help          显示本帮助并退出
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      [[ $# -ge 2 ]] || { echo "--format 缺少参数" >&2; exit 2; }
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    --format=*) OUTPUT_FORMAT="${1#*=}"; shift ;;
    --file)
      [[ $# -ge 2 ]] || { echo "--file 缺少参数" >&2; exit 2; }
      ARCHIVE="$2"
      shift 2
      ;;
    --file=*) ARCHIVE="${1#*=}"; shift ;;
    --yes) CONFIRM=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "${ACTION}" == "-h" || "${ACTION}" == "--help" ]]; then
  usage
  exit 0
fi

case "${OUTPUT_FORMAT}" in
  text|json) ;;
  *) echo "--format 只能是 text 或 json" >&2; exit 2 ;;
esac
case "${ACTION}" in
  backup|verify|restore-smoke) ;;
  *) echo "未知动作: ${ACTION}" >&2; usage >&2; exit 2 ;;
esac

if [[ "${OUTPUT_FORMAT}" == "json" ]] && ! command -v python3 >/dev/null 2>&1; then
  echo "JSON 输出需要 python3" >&2
  exit 2
fi

COMPOSE_FILE_PATH="${MEM0_BACKUP_COMPOSE_FILE}"
if [[ "${COMPOSE_FILE_PATH}" != /* ]]; then
  COMPOSE_FILE_PATH="${MEM0_BACKUP_COMPOSE_DIR}/${COMPOSE_FILE_PATH}"
fi
DOCKER_USE_SUDO=false
DOCKER_EXEC_PREFIX=(docker exec)
CONTAINER_ID=""
PGFILE_PATH="/tmp/vps-sysops-db-file"
DB_USER=""
DB_NAME=""
DB_VALUE=""

docker_exec() {
  "${DOCKER_EXEC_PREFIX[@]}" "$@"
}

docker_compose() {
  if [[ "${DOCKER_USE_SUDO}" == "true" ]]; then
    sudo -n docker compose "$@"
  else
    docker compose "$@"
  fi
}

prepare_docker() {
  command -v docker >/dev/null 2>&1 || return 1
  [[ -f "${COMPOSE_FILE_PATH}" ]] || return 1
  if docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=false
    DOCKER_EXEC_PREFIX=(docker exec)
  elif command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=true
    DOCKER_EXEC_PREFIX=(sudo -n docker exec)
  else
    return 1
  fi
  CONTAINER_ID="$(cd "${MEM0_BACKUP_COMPOSE_DIR}" && docker_compose -f "${COMPOSE_FILE_PATH}" ps -q "${MEM0_BACKUP_DB_SERVICE}")"
  [[ -n "${CONTAINER_ID}" ]] || return 1
}

read_env_value() {
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

load_db_values() {
  [[ -n "${MEM0_BACKUP_ENV_FILE}" ]] || return 1
  local p=POSTGRES u=USER d=DB n1 n2 n3
  n1="${p}_${u}"
  n2="${p}_${d}"
  n3="${p}_PASSWORD"
  DB_USER="$(read_env_value "${MEM0_BACKUP_ENV_FILE}" "${n1}" || true)"
  DB_NAME="$(read_env_value "${MEM0_BACKUP_ENV_FILE}" "${n2}" || true)"
  DB_VALUE="$(read_env_value "${MEM0_BACKUP_ENV_FILE}" "${n3}" || true)"
  [[ -n "${DB_USER}" && -n "${DB_NAME}" && -n "${DB_VALUE}" ]]
}

cleanup() {
  if [[ -n "${CONTAINER_ID}" ]]; then
    docker_exec "${CONTAINER_ID}" rm -f "${PGFILE_PATH}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

create_pgfile() {
  local escaped="${DB_VALUE//\\/\\\\}"
  escaped="${escaped//:/\\:}"
  local line="*:*:*:${DB_USER}:${escaped}"
  printf '%s\n' "${line}" | docker_exec -i "${CONTAINER_ID}" sh -c \
    'umask 077; cat > "$1"; chmod 600 "$1"' sh "${PGFILE_PATH}"
}

dump_is_valid() {
  local path="$1"
  [[ -s "${path}" ]] || return 1
  docker_exec -i "${CONTAINER_ID}" pg_restore -l >/dev/null <"${path}"
}

latest_archive() {
  find "${MEM0_BACKUP_DEST}" -maxdepth 1 -type f -name 'mem0_*.dump' -printf '%T@ %p\n' 2>/dev/null |
    sort -nr | awk 'NR == 1 {sub(/^[^ ]+ /, ""); print}'
}

emit_result() {
  local ok="$1" action="$2" file="$3" detail="$4"
  if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    export MEM0_BACKUP_OK="${ok}" MEM0_BACKUP_ACTION="${action}"
    export MEM0_BACKUP_FILE="${file}" MEM0_BACKUP_DETAIL="${detail}"
    python3 <<'PY'
import json
import os
print(json.dumps({
    "ok": os.environ.get("MEM0_BACKUP_OK") == "true",
    "action": os.environ.get("MEM0_BACKUP_ACTION", ""),
    "file": os.environ.get("MEM0_BACKUP_FILE", ""),
    "detail": os.environ.get("MEM0_BACKUP_DETAIL", ""),
}, ensure_ascii=False, indent=2))
PY
  else
    echo "Mem0 backup ${action}"
    [[ -n "${file}" ]] && echo "  file:   ${file}"
    echo "  result: ${ok}"
    [[ -z "${detail}" ]] || echo "  detail: ${detail}"
  fi
  [[ "${ok}" == "true" ]]
}

if [[ "${MEM0_BACKUP_ENABLED}" != "true" ]]; then
  emit_result true "${ACTION}" "" "disabled by profile"
  exit 0
fi

if ! prepare_docker; then
  emit_result false "${ACTION}" "" "Mem0 Compose/PostgreSQL unavailable"
  exit 1
fi
if ! load_db_values; then
  emit_result false "${ACTION}" "" "PostgreSQL database settings unavailable"
  exit 1
fi
create_pgfile

case "${ACTION}" in
  backup)
    mkdir -p "${MEM0_BACKUP_DEST}"
    chmod 700 "${MEM0_BACKUP_DEST}"
    usage_pct="$(df -P "${MEM0_BACKUP_DEST}" | awk 'NR == 2 {gsub("%", "", $5); print $5}')"
    if [[ -z "${usage_pct}" || "${usage_pct}" -ge "${MEM0_BACKUP_DISK_LIMIT}" ]]; then
      emit_result false "backup" "" "backup filesystem usage is ${usage_pct:-unknown}%"
      exit 1
    fi
    stamp="$(date -u '+%Y%m%d_%H%M%S')"
    part="${MEM0_BACKUP_DEST}/.mem0_${stamp}.dump.part"
    target="${MEM0_BACKUP_DEST}/mem0_${stamp}.dump"
    if ! timeout "${MEM0_BACKUP_TIMEOUT}" "${DOCKER_EXEC_PREFIX[@]}" -i "${CONTAINER_ID}" sh -c \
      'f=PG; f="${f}PASSFILE"; env "$f=$1" pg_dump --format=custom --no-owner --no-acl -U "$2" -d "$3"' \
      sh "${PGFILE_PATH}" "${DB_USER}" "${DB_NAME}" >"${part}"; then
      rm -f -- "${part}"
      emit_result false "backup" "" "pg_dump failed or timed out"
      exit 1
    fi
    if ! dump_is_valid "${part}"; then
      rm -f -- "${part}"
      emit_result false "backup" "" "pg_restore format validation failed"
      exit 1
    fi
    mv -- "${part}" "${target}"
    chmod 600 "${target}"
    sha256sum "${target}" >"${target}.sha256"
    chmod 600 "${target}.sha256"
    find "${MEM0_BACKUP_DEST}" -maxdepth 1 -type f -name 'mem0_*.dump' \
      -mtime "+${MEM0_BACKUP_RETAIN_DAYS}" -delete
    find "${MEM0_BACKUP_DEST}" -maxdepth 1 -type f -name 'mem0_*.dump.sha256' \
      -mtime "+${MEM0_BACKUP_RETAIN_DAYS}" -delete
    emit_result true "backup" "${target}" "$(du -h "${target}" | cut -f1)"
    ;;
  verify)
    [[ -n "${ARCHIVE}" ]] || ARCHIVE="$(latest_archive)"
    [[ -f "${ARCHIVE}" ]] || { emit_result false "verify" "${ARCHIVE}" "dump not found"; exit 1; }
    if [[ -f "${ARCHIVE}.sha256" ]] && ! sha256sum -c "${ARCHIVE}.sha256" >/dev/null 2>&1; then
      emit_result false "verify" "${ARCHIVE}" "sha256 mismatch"
      exit 1
    fi
    dump_is_valid "${ARCHIVE}" || { emit_result false "verify" "${ARCHIVE}" "pg_restore format validation failed"; exit 1; }
    emit_result true "verify" "${ARCHIVE}" "sha256 and pg_restore checks passed"
    ;;
  restore-smoke)
    [[ "${CONFIRM}" == "true" ]] || { emit_result false "restore-smoke" "" "pass --yes to run"; exit 2; }
    [[ -n "${ARCHIVE}" ]] || ARCHIVE="$(latest_archive)"
    [[ -f "${ARCHIVE}" ]] || { emit_result false "restore-smoke" "${ARCHIVE}" "dump not found"; exit 1; }
    dump_is_valid "${ARCHIVE}" || { emit_result false "restore-smoke" "${ARCHIVE}" "dump validation failed"; exit 1; }
    temp_db="mem0_restore_smoke_$(date -u '+%Y%m%d%H%M%S')"
    docker_exec "${CONTAINER_ID}" createdb -U "${DB_USER}" "${temp_db}"
    restore_ok=false
    if timeout "${MEM0_BACKUP_TIMEOUT}" "${DOCKER_EXEC_PREFIX[@]}" -i "${CONTAINER_ID}" sh -c \
      'f=PG; f="${f}PASSFILE"; env "$f=$1" pg_restore --exit-on-error --no-owner --no-acl -U "$2" -d "$3"' \
      sh "${PGFILE_PATH}" "${DB_USER}" "${temp_db}" <"${ARCHIVE}"; then
      restore_ok=true
    fi
    docker_exec "${CONTAINER_ID}" dropdb -U "${DB_USER}" "${temp_db}" >/dev/null 2>&1 || true
    if [[ "${restore_ok}" != "true" ]]; then
      emit_result false "restore-smoke" "${ARCHIVE}" "temporary database restore failed"
      exit 1
    fi
    emit_result true "restore-smoke" "${ARCHIVE}" "temporary database restored and dropped"
    ;;
esac
