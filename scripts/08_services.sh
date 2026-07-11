#!/usr/bin/env bash
# 08_services.sh —— 服务管理
# 用法: bash 08_services.sh
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

# 用法说明（bash scripts/08_services.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/08_services.sh

服务管理

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 4. 服务管理 ──────────────────────────────────────────────────────────────
cmd_services() {
  title "服务管理"

  section "关键服务状态"
  local services=("ssh" "ufw" "fail2ban" "nginx" "apache2" "mysql" "postgresql"
                  "docker" "google-cloud-ops-agent" "stackdriver-agent" "chronyd" "ntp")
  printf "%-35s %-15s %s\\n" "服务名称" "状态" "说明"
  printf "%-35s %-15s %s\\n" "$(printf '─%.0s' {1..35})" "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..20})"
  for svc in "${services[@]}"; do
    if systemctl list-units --type=service --all | grep -q "${svc}.service"; then
      local status
      status=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
      local color="\e[32m"
      [[ "$status" != "active" ]] && color="\e[31m"
      local enabled
      enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "N/A")
      printf "%-35s ${color}%-15s\e[0m %s\\n" "$svc" "$status" "enabled=$enabled"
    fi
  done

  section "最近启动/停止的服务（最近 10 条）"
  journalctl --no-pager -n 200 --since "24 hours ago" -o short-iso 2>/dev/null | \
    grep -E "Started|Stopped|Failed" | tail -10 || \
    warn "journalctl 查询失败，请以 root 运行"

  section "监听端口"
  ss -tlnp 2>/dev/null | grep -v '127.0.0.53' || netstat -tlnp 2>/dev/null || warn "ss/netstat 不可用"
}

# 主入口
cmd_services