#!/usr/bin/env bash
# 04_backup.sh —— 备份指定目录 + 配置日志轮转，可加入 cron 定时执行
# 用法: bash 04_backup.sh（写 /etc/logrotate.d 需要 root，其余部分普通用户也可运行）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

# 用法说明（bash scripts/04_backup.sh [-h|--help]）
usage() {
  cat <<EOF
用法: sudo bash scripts/04_backup.sh

备份指定目录 + 配置日志轮转，可加入 cron 定时执行

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "${BACKUP_DEST}"
STAMP=$(date '+%Y%m%d_%H%M%S')
ARCHIVE="${BACKUP_DEST}/backup_${STAMP}.tar.gz"

echo "备份目录: ${BACKUP_SOURCES}"
tar -czf "${ARCHIVE}" ${BACKUP_SOURCES} 2>/tmp/vps-ops-backup-errors.log || true
echo "已生成备份: ${ARCHIVE} ($(du -h "${ARCHIVE}" | cut -f1))"

# 清理过期备份
find "${BACKUP_DEST}" -name 'backup_*.tar.gz' -mtime +"${BACKUP_RETAIN_DAYS}" -print -delete

# 配置日志轮转（仅在 root 权限下写入）
LOGROTATE_CONF="/etc/logrotate.d/vps-ops"
if [[ $EUID -eq 0 && ! -f "${LOGROTATE_CONF}" ]]; then
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
else
  echo "跳过 logrotate 配置写入（非 root 或已存在），如需生效请以 sudo 重新运行一次"
fi
