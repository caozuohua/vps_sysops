#!/usr/bin/env bash
# 12_disk.sh —— 磁盘与存储（使用率 / inode / 大文件 / 大目录 / 挂载 / SMART）
# 用法: bash 12_disk.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

log() { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }
title() { echo -e "\n\e[1;34m═══════════════════════════════════════\e[0m"; \
          echo -e "\e[1;36m  $*\e[0m"; \
          echo -e "\e[1;34m═══════════════════════════════════════\e[0m"; }
section() { echo -e "\n\e[1;33m▶ $*\e[0m"; echo "$(printf '─%.0s' {1..40})"; }

# 用法说明（bash scripts/12_disk.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/12_disk.sh

磁盘与存储（使用率 / inode / 大文件 / 大目录 / 挂载 / SMART）

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 8. 磁盘与存储 ────────────────────────────────────────────────────────────
cmd_disk() {
  title "磁盘与存储"

  section "磁盘使用情况"
  df -hT | grep -v tmpfs | grep -v devtmpfs

  section "inode 使用情况"
  df -i | grep -v tmpfs | grep -v devtmpfs | \
    awk 'NR==1{print} NR>1{
      pct=$5; gsub(/%/,"",pct);
      if(pct+0 >= 90) printf "\e[31m%s\e[0m\n", $0
      else print
    }'

  section "大文件 Top 20（全盘，>100MB）"
  find / -xdev -type f -size +100M 2>/dev/null | \
    xargs ls -lh 2>/dev/null | sort -k5 -rh | head -20 | \
    awk '{printf "%-10s %s\n", $5, $9}'

  section "大目录 Top 10（/var, /home, /opt）"
  du -sh /var /home /opt /tmp /usr 2>/dev/null | sort -rh | head -10

  section "挂载点与磁盘类型"
  lsblk -f 2>/dev/null || fdisk -l 2>/dev/null | grep "Disk /"

  section "磁盘健康（smartctl）"
  if command -v smartctl &>/dev/null; then
    lsblk -d -o NAME 2>/dev/null | tail -n +2 | while read -r disk; do
      echo "── /dev/${disk}:"
      smartctl -H "/dev/${disk}" 2>/dev/null | grep "SMART overall" || echo "  N/A（虚拟磁盘或权限不足）"
    done
  else
    warn "smartctl 未安装（GCP 实例使用虚拟磁盘，通常无需）"
  fi
}

# 主入口
cmd_disk
