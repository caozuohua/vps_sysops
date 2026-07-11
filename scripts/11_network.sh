#!/usr/bin/env bash
# 11_network.sh —— 网络诊断（接口 / 路由 / DNS / GCP 连通性 / 活跃连接 / 流量统计）
# 用法: bash 11_network.sh
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

# 用法说明（bash scripts/11_network.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/11_network.sh

网络诊断（接口 / 路由 / DNS / GCP 连通性 / 活跃连接 / 流量统计）

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 7. 网络诊断 ──────────────────────────────────────────────────────────────
cmd_network() {
  title "网络诊断"

  section "网络接口详情"
  ip addr show | grep -E "^[0-9]+:|inet " | grep -v '127.0.0.1'

  section "路由表"
  ip route show

  section "DNS 解析"
  echo "DNS 服务器: $(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')"
  echo -n "解析测试 (google.com): "
  dig +short google.com 2>/dev/null | head -1 || nslookup google.com 2>/dev/null | grep Address | tail -1 || echo "失败"

  section "GCP 连接性测试"
  local endpoints=("metadata.google.internal:80" "storage.googleapis.com:443" "compute.googleapis.com:443")
  for ep in "${endpoints[@]}"; do
    local host="${ep%%:*}"
    local port="${ep##*:}"
    if timeout 3 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
      echo -e "\e[32m✓\e[0m ${ep}"
    else
      echo -e "\e[31m✗\e[0m ${ep} (不可达)"
    fi
  done

  section "活跃网络连接 Top 5（远程 IP）"
  ss -tn state established 2>/dev/null | awk 'NR>1{print $5}' | \
    cut -d: -f1 | sort | uniq -c | sort -rn | head -5 || true

  section "网络统计"
  if [[ -f /proc/net/dev ]]; then
    awk 'NR>2 && $1!="lo:" {
      gsub(/:/, "", $1)
      printf "%-12s RX: %-15s TX: %-15s\n", $1,
        (($2/1024/1024 > 1) ? sprintf("%.1f MB", $2/1024/1024) : sprintf("%.1f KB", $2/1024)),
        (($10/1024/1024 > 1) ? sprintf("%.1f MB", $10/1024/1024) : sprintf("%.1f KB", $10/1024))
    }' /proc/net/dev
  fi
}

# 主入口
cmd_network
