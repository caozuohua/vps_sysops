#!/usr/bin/env bash
# 06_processes.sh —— 进程管理
# 用法: bash 06_processes.sh
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

# 用法说明（bash scripts/06_processes.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/06_processes.sh

进程管理

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 3. 进程管理 ──────────────────────────────────────────────────────────────
cmd_processes() {
  title "进程管理"

  section "CPU 占用 Top 10"
  ps aux --sort=-%cpu | head -11 | \
    awk 'NR==1{printf "%-8s %-6s %-5s %-5s %-10s %s\n", "USER", "PID", "%CPU", "%MEM", "STATUS", "COMMAND"}
         NR>1{printf "%-8s %-6s %-5s %-5s %-10s %s\n", $1, $2, $3, $4, $8, substr($0, index($0,$11), 40)}'

  section "内存占用 Top 10"
  ps aux --sort=-%mem | head -11 | \
    awk 'NR==1{printf "%-8s %-6s %-5s %-5s %-10s %s\n", "USER", "PID", "%CPU", "%MEM", "STATUS", "COMMAND"}
         NR>1{printf "%-8s %-6s %-5s %-5s %-10s %s\n", $1, $2, $3, $4, $8, substr($0, index($0,$11), 40)}'

  section "僵尸进程检查"
  local zombies
  zombies=$(ps aux | awk '$8=="Z"' | wc -l)
  if [[ $zombies -gt 0 ]]; then
    warn "发现 ${zombies} 个僵尸进程："
    ps aux | awk 'NR==1 || $8=="Z"'
  else
    log "无僵尸进程"
  fi

  section "系统进程总数"
  echo "运行中: $(ps aux | grep -c ' R ')"
  echo "休眠中: $(ps aux | grep -c ' S ')"
  echo "总计:   $(ps aux | wc -l)"
}

# 主入口
cmd_processes
