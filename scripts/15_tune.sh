#!/usr/bin/env bash
# 15_tune.sh —— 性能参数检查 & 调优建议
# 用法: bash 15_tune.sh
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

# 用法说明（bash scripts/15_tune.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/15_tune.sh

性能参数检查 & 调优建议

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 11. 性能调优 ────────────────────────────────────────────────────────────
cmd_tune() {
  title "性能状态与调优建议"

  section "当前 sysctl 关键参数"
  local params=(
    "vm.swappiness"
    "net.core.somaxconn"
    "net.ipv4.tcp_max_syn_backlog"
    "net.ipv4.tcp_fin_timeout"
    "net.ipv4.tcp_tw_reuse"
    "net.core.rmem_max"
    "net.core.wmem_max"
    "fs.file-max"
  )
  for p in "${params[@]}"; do
    printf "%-40s = %s\n" "$p" "$(sysctl -n "$p" 2>/dev/null || echo 'N/A')"
  done

  section "文件描述符"
  echo "系统上限: $(sysctl -n fs.file-max 2>/dev/null)"
  echo "当前使用: $(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1}')"

  section "透明大页（THP）"
  local thp
  thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo 'N/A')
  echo "THP 状态: $thp"
  echo "$thp" | grep -q '\[always\]' && warn "建议数据库场景关闭 THP：echo never > /sys/kernel/mm/transparent_hugepage/enabled"

  section "调优建议"
  local mem_gb
  mem_gb=$(free -g | awk 'NR==2{print $2}')

  local swappiness
  swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo 60)
  [[ $swappiness -gt 10 ]] && warn "vm.swappiness=${swappiness}，建议 Web 服务器设为 10：sysctl -w vm.swappiness=10"

  local somaxconn
  somaxconn=$(sysctl -n net.core.somaxconn 2>/dev/null || echo 128)
  [[ $somaxconn -lt 1024 ]] && warn "net.core.somaxconn=${somaxconn}，高并发场景建议 ≥ 1024"

  echo ""
  cat <<'EOF'
  推荐 /etc/sysctl.d/99-gcp-optimize.conf 配置：
  ──────────────────────────────────────────────
  vm.swappiness = 10
  net.core.somaxconn = 65535
  net.ipv4.tcp_max_syn_backlog = 65535
  net.ipv4.tcp_fin_timeout = 15
  net.ipv4.tcp_tw_reuse = 1
  net.core.rmem_max = 16777216
  net.core.wmem_max = 16777216
  fs.file-max = 2097152
  ──────────────────────────────────────────────
  应用：sysctl --system
EOF
}

# 主入口
cmd_tune
