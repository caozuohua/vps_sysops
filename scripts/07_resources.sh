#!/usr/bin/env bash
# 07_resources.sh —— 资源监控
# 用法: bash 07_resources.sh
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

# 用法说明（bash scripts/07_resources.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/07_resources.sh

资源监控

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 2. 资源监控 ──────────────────────────────────────────────────────────────
cmd_resources() {
  title "资源监控"

  section "CPU"
  echo "处理器型号:   $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
  echo "物理核心数:   $(grep -c '^processor' /proc/cpuinfo)"
  local idle
  idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | tr -d '%id,')
  echo "CPU 使用率:   $(echo "100 - ${idle:-0}" | bc 2>/dev/null || echo 'N/A')%"
  echo "负载均衡:     $(cat /proc/loadavg | awk '{print "1min="$1, "5min="$2, "15min="$3}')"

  section "内存"
  free -h | awk '
    NR==1 {printf "%-12s %8s %8s %8s %8s\n", "", $1, $2, $3, $4}
    NR==2 {printf "%-12s %8s %8s %8s %8s\n", "RAM:", $2, $3, $4, $6}
    NR==3 {printf "%-12s %8s %8s %8s\n", "Swap:", $2, $3, $4}'
  local mem_used mem_total mem_pct
  mem_used=$(free -m | awk 'NR==2{print $3}')
  mem_total=$(free -m | awk 'NR==2{print $2}')
  mem_pct=$(awk "BEGIN{printf \"%.1f\", ${mem_used}/${mem_total}*100}" 2>/dev/null || echo 0)
  echo "内存使用率:   ${mem_pct}%"
  [[ $(echo "$mem_pct > ${MEM_THRESHOLD:-85}" | bc 2>/dev/null) -eq 1 ]] && warn "内存使用率超过 ${MEM_THRESHOLD:-85}%，请关注！"

  section "磁盘空间"
  df -hT | grep -v tmpfs | grep -v devtmpfs | \
    awk 'NR==1{print} NR>1{
      pct=$6; gsub(/%/,"",pct);
      if(pct+0 >= 90) printf "\e[31m%s\e[0m\n", $0
      else if(pct+0 >= 75) printf "\e[33m%s\e[0m\n", $0
      else print
    }'

  section "磁盘 I/O（iostat，若可用）"
  if command -v iostat &>/dev/null; then
    iostat -x 1 1 | grep -v '^$' | tail -n +3
  else
    warn "iostat 未安装，跳过（安装：apt install sysstat）"
  fi

  section "网络接口"
  ip -br addr show | grep -v '^lo'
  echo ""
  if command -v ss &>/dev/null; then
    echo "TCP 连接状态统计:"
    ss -s | grep -E "TCP|estab|closed|time-wait"
  fi
}

# 主入口
cmd_resources
