#!/usr/bin/env bash
# 04_backup.sh —— 备份指定目录 + 配置日志轮转，可加入 cron 定时执行
# 用法: sudo bash 04_backup.sh（主机 profile 包含 root-only 配置和数据库）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

# 用法说明（bash scripts/04_backup.sh [-h|--help]）
usage() {
  cat <<EOF
用法: sudo bash scripts/04_backup.sh

备份指定目录、生成 SQLite 一致性副本并配置日志轮转，可加入 cron 定时执行

可选环境变量:
  VPS_PROFILE=gcp|azure   显式选择主机配置（已知主机会按 hostname 自动选择）

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "默认备份源包含 /etc 和 /home，请使用 root 权限运行" >&2
  exit 1
fi

umask 077
mkdir -p "${BACKUP_DEST}"
chmod 700 "${BACKUP_DEST}"

read -r -a SOURCES <<< "${BACKUP_SOURCES}"
for source in "${SOURCES[@]}"; do
  [[ "${source}" == /* ]] || { echo "备份源必须是绝对路径: ${source}" >&2; exit 1; }
  [[ -e "$source" ]] || { echo "备份源不存在: $source" >&2; exit 1; }
done

STAMP=$(date '+%Y%m%d_%H%M%S')
ARCHIVE="${BACKUP_DEST}/backup_${STAMP}.tar.gz"
STAGE_DIR=$(mktemp -d "${BACKUP_DEST}/.stage_${STAMP}_XXXXXX")
trap 'rm -rf -- "${STAGE_DIR}"' EXIT

# SQLite 数据库不能依赖普通 tar 的时点一致性。先用在线 backup API 生成副本并校验。
if [[ -n "${SQLITE_DATABASES:-}" ]]; then
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "配置了 SQLITE_DATABASES，但系统缺少 sqlite3" >&2
    exit 1
  }
  mkdir -p "${STAGE_DIR}/sqlite"
  for database in ${SQLITE_DATABASES}; do
    [[ -f "${database}" ]] || { echo "SQLite 数据库不存在: ${database}" >&2; exit 1; }
    safe_name=$(printf '%s' "${database#/}" | tr '/ ' '__')
    snapshot="${STAGE_DIR}/sqlite/${safe_name}.sqlite3"
    sqlite3 "${database}" ".timeout 5000" ".backup '${snapshot}'"
    integrity=$(sqlite3 "${snapshot}" 'PRAGMA integrity_check;')
    [[ "${integrity}" == "ok" ]] || {
      echo "SQLite 备份完整性检查失败: ${database}: ${integrity}" >&2
      exit 1
    }
    echo "SQLite 一致性副本: ${database} -> ${safe_name}.sqlite3"
  done
fi

echo "备份目录: ${BACKUP_SOURCES}"
if [[ -d "${STAGE_DIR}/sqlite" ]]; then
  tar_args=("${SOURCES[@]}" -C "${STAGE_DIR}" sqlite)
else
  tar_args=("${SOURCES[@]}")
fi
if ! tar -czf "${ARCHIVE}" "${tar_args[@]}" 2>/tmp/vps-ops-backup-errors.log; then
  rm -f "${ARCHIVE}"
  echo "备份失败，详情见 /tmp/vps-ops-backup-errors.log" >&2
  exit 1
fi
chmod 600 "${ARCHIVE}"
tar -tzf "${ARCHIVE}" >/dev/null
sha256sum "${ARCHIVE}" > "${ARCHIVE}.sha256"
chmod 600 "${ARCHIVE}.sha256"
echo "已生成备份: ${ARCHIVE} ($(du -h "${ARCHIVE}" | cut -f1))"

# 清理过期备份
find "${BACKUP_DEST}" -name 'backup_*.tar.gz' -mtime +"${BACKUP_RETAIN_DAYS}" -print -delete
find "${BACKUP_DEST}" -name 'backup_*.tar.gz.sha256' -mtime +"${BACKUP_RETAIN_DAYS}" -print -delete

# 配置日志轮转
LOGROTATE_CONF="/etc/logrotate.d/vps-ops"
if [[ "${CONFIGURE_LOGROTATE:-true}" == "true" && ! -f "${LOGROTATE_CONF}" ]]; then
  cat > "${LOGROTATE_CONF}" <<'EOF'
/var/log/vps-ops-*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF
  echo "已写入 logrotate 配置: ${LOGROTATE_CONF}"
elif [[ "${CONFIGURE_LOGROTATE:-true}" != "true" ]]; then
  echo "profile 已禁用 logrotate 配置写入"
else
  echo "logrotate 配置已存在: ${LOGROTATE_CONF}"
fi
