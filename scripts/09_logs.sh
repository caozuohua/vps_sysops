#!/usr/bin/env bash
# 09_logs.sh —— 日志分析（错误日志 / 认证失败 / OOM / 磁盘错误 / 大日志文件）
# 用法: bash 09_logs.sh
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

# 用法说明（bash scripts/09_logs.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/09_logs.sh

日志分析（错误日志 / 认证失败 / OOM / 磁盘错误 / 大日志文件）

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 5. 日志分析 ──────────────────────────────────────────────────────────────
cmd_logs() {
  title "日志分析"

  section "系统错误（最近 24h，syslog）"
  if [[ -f /var/log/syslog ]]; then
    grep -i "error\|critical\|panic\|oops" /var/log/syslog | \
      grep "$(date '+%b %_d')\|$(date -d '1 day ago' '+%b %_d' 2>/dev/null)" 2>/dev/null | \
      tail -20 || echo "无错误日志"
  else
    journalctl -p err --since "24 hours ago" --no-pager 2>/dev/null | tail -20 || \
      warn "日志读取失败"
  fi

  section "认证失败（最近 50 条）"
  if [[ -f /var/log/auth.log ]]; then
    grep -i "failed\|invalid\|authentication failure" /var/log/auth.log | tail -20 || \
      echo "无认证失败记录"
  else
    journalctl -u ssh --since "24 hours ago" --no-pager 2>/dev/null | \
      grep -i "failed\|invalid" | tail -20 || warn "SSH 日志读取失败"
  fi

  section "内核 OOM 事件"
  if dmesg 2>/dev/null | grep -qi "out of memory\|oom-killer"; then
    warn "检测到 OOM 事件："
    dmesg 2>/dev/null | grep -i "out of memory\|oom-killer" | tail -10
  else
    log "无 OOM 事件"
  fi

  section "磁盘错误"
  dmesg 2>/dev/null | grep -iE "I/O error|disk|ext4|filesystem" | tail -10 || echo "无磁盘错误"

  section "大日志文件 Top 10（/var/log）"
  find /var/log -type f \( -name "*.log" -o -name "*.log.*" \) 2>/dev/null | \
    xargs ls -lh 2>/dev/null | sort -k5 -rh | head -10 | \
    awk '{printf "%-10s %s\n", $5, $9}'
}

# 主入口
cmd_logs
