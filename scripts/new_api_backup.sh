#!/usr/bin/env bash
# new_api_backup.sh — service-scoped new-api backup and archive verification
set -euo pipefail

NEW_API_HOME="${NEW_API_HOME:-/root/new-api}"
NEW_API_ENV="${NEW_API_ENV:-${NEW_API_HOME}/.env}"
NEW_API_DB="${NEW_API_DB:-${NEW_API_HOME}/data/one-api.db}"
NEW_API_BACKUP_DEST="${NEW_API_BACKUP_DEST:-/var/backups/vps-sysops/new-api}"
NEW_API_BACKUP_RETAIN_DAYS="${NEW_API_BACKUP_RETAIN_DAYS:-14}"
NEW_API_BACKUP_MIN_FREE_MB="${NEW_API_BACKUP_MIN_FREE_MB:-256}"

usage() {
  cat <<'EOF'
用法: sudo bash scripts/new_api_backup.sh [backup|verify ARCHIVE]

backup  备份 new-api .env 和 SQLite 在线快照，并生成 SHA-256 校验文件
verify  校验归档、解压临时副本并执行 SQLite integrity_check
EOF
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || { echo "new-api backup requires root" >&2; exit 1; }
}

require_commands() {
  local command_name
  for command_name in sqlite3 tar sha256sum install df mktemp; do
    command -v "${command_name}" >/dev/null 2>&1 || {
      echo "missing required command: ${command_name}" >&2
      exit 1
    }
  done
}

safe_archive_path() {
  local path="$1"
  [[ "${path}" == "${NEW_API_BACKUP_DEST}"/new-api_*.tar.gz ]] || {
    echo "archive must be under ${NEW_API_BACKUP_DEST}" >&2
    exit 1
  }
}

verify_archive() {
  local archive="$1"
  safe_archive_path "${archive}"
  [[ -f "${archive}" && -f "${archive}.sha256" ]] || {
    echo "archive or checksum not found: ${archive}" >&2
    exit 1
  }

  sha256sum -c "${archive}.sha256"
  local verify_dir
  verify_dir=$(mktemp -d /tmp/new-api-backup-verify.XXXXXX)
  trap 'rm -rf -- "${verify_dir:-}"' RETURN
  tar -xzf "${archive}" -C "${verify_dir}"
  [[ -f "${verify_dir}/new-api/.env" ]] || { echo "archive missing .env" >&2; exit 1; }
  local snapshot="${verify_dir}/new-api/data/one-api.db.sqlite3"
  [[ -f "${snapshot}" ]] || { echo "archive missing SQLite snapshot" >&2; exit 1; }
  [[ "$(sqlite3 "${snapshot}" 'PRAGMA integrity_check;')" == "ok" ]] || {
    echo "SQLite integrity check failed" >&2
    exit 1
  }
  echo "new-api backup verify ok: ${archive}"
}

backup() {
  [[ -f "${NEW_API_ENV}" ]] || { echo "new-api env not found: ${NEW_API_ENV}" >&2; exit 1; }
  [[ -f "${NEW_API_DB}" ]] || { echo "new-api database not found: ${NEW_API_DB}" >&2; exit 1; }
  mkdir -p "${NEW_API_BACKUP_DEST}"
  chmod 700 "${NEW_API_BACKUP_DEST}"

  local free_kb
  free_kb=$(df -Pk "${NEW_API_BACKUP_DEST}" | awk 'NR == 2 {print $4}')
  (( free_kb >= NEW_API_BACKUP_MIN_FREE_MB * 1024 )) || {
    echo "insufficient backup disk space: ${free_kb} KB free" >&2
    exit 1
  }

  local stamp archive stage snapshot integrity
  stamp=$(date -u '+%Y%m%d_%H%M%S')
  archive="${NEW_API_BACKUP_DEST}/new-api_${stamp}.tar.gz"
  stage=$(mktemp -d "${NEW_API_BACKUP_DEST}/.stage_${stamp}_XXXXXX")
  trap 'rm -rf -- "${stage:-}"' RETURN
  mkdir -p "${stage}/new-api/data"

  snapshot="${stage}/new-api/data/one-api.db.sqlite3"
  sqlite3 "${NEW_API_DB}" ".timeout 5000" ".backup '${snapshot}'"
  integrity=$(sqlite3 "${snapshot}" 'PRAGMA integrity_check;')
  [[ "${integrity}" == "ok" ]] || {
    echo "SQLite integrity check failed: ${integrity}" >&2
    exit 1
  }
  install -m 600 "${NEW_API_ENV}" "${stage}/new-api/.env"
  {
    echo "service=new-api"
    echo "created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if command -v docker >/dev/null 2>&1; then
      docker inspect new-api --format 'image={{.Config.Image}}' 2>/dev/null || true
    fi
  } >"${stage}/manifest.txt"
  chmod 600 "${stage}/manifest.txt"

  tar -czf "${archive}" -C "${stage}" new-api manifest.txt
  chmod 600 "${archive}"
  tar -tzf "${archive}" >/dev/null
  sha256sum "${archive}" >"${archive}.sha256"
  chmod 600 "${archive}.sha256"
  verify_archive "${archive}"
  find "${NEW_API_BACKUP_DEST}" -maxdepth 1 -name 'new-api_*.tar.gz' \
    -mtime "+${NEW_API_BACKUP_RETAIN_DAYS}" -delete
  find "${NEW_API_BACKUP_DEST}" -maxdepth 1 -name 'new-api_*.tar.gz.sha256' \
    -mtime "+${NEW_API_BACKUP_RETAIN_DAYS}" -delete
  echo "new-api backup ok: ${archive}"
  echo "new-api backup verify: ${archive}.sha256"
}

require_root
require_commands
action="${1:-backup}"
case "${action}" in
  -h|--help) usage ;;
  backup) backup ;;
  verify)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    verify_archive "$2"
    ;;
  *) usage >&2; exit 2 ;;
esac
