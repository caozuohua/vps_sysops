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

  user_systemctl() {
    local target_user="${MONITOR_USER:-$(id -un)}"
    local target_uid
    target_uid=$(id -u "${target_user}" 2>/dev/null) || return 1
    [[ -d "/run/user/${target_uid}" ]] || return 1
    if [[ "$(id -un)" == "${target_user}" ]]; then
      XDG_RUNTIME_DIR="/run/user/${target_uid}" systemctl --user "$@"
    elif [[ $EUID -eq 0 ]] && command -v runuser >/dev/null 2>&1; then
      runuser -u "${target_user}" -- env XDG_RUNTIME_DIR="/run/user/${target_uid}" \
        systemctl --user "$@"
    else
      return 1
    fi
  }

  declare -A seen_units=()
  print_unit() {
    local requested="$1" required="${2:-no}"
    local unit="${requested}" load status enabled scope color
    [[ "${unit}" == *.* ]] || unit="${unit}.service"
    [[ -n "${seen_units[$unit]:-}" ]] && return 0
    seen_units["$unit"]=1

    load=$(systemctl show "${unit}" --property=LoadState --value 2>/dev/null || true)
    if [[ -n "${load}" && "${load}" != "not-found" ]]; then
      scope="system"
      status=$(systemctl is-active "${unit}" 2>/dev/null || true)
      enabled=$(systemctl is-enabled "${unit}" 2>/dev/null || echo "N/A")
    else
      load=$(user_systemctl show "${unit}" --property=LoadState --value 2>/dev/null || true)
      if [[ -n "${load}" && "${load}" != "not-found" ]]; then
        scope="user:${MONITOR_USER:-$(id -un)}"
        status=$(user_systemctl is-active "${unit}" 2>/dev/null || true)
        enabled=$(user_systemctl is-enabled "${unit}" 2>/dev/null || echo "N/A")
      elif [[ "${required}" == "yes" ]]; then
        printf "%-35s \e[31m%-15s\e[0m %s\\n" "${unit}" "missing" "profile=${VPS_PROFILE:-generic}"
        return 0
      else
        return 0
      fi
    fi

    color="\e[32m"
    [[ "${status}" != "active" ]] && color="\e[31m"
    printf "%-35s ${color}%-15s\e[0m %s\\n" "${unit}" "${status}" "${scope}, enabled=${enabled}"
  }

  section "主机 profile 监控服务"
  echo "VPS profile: ${VPS_PROFILE:-generic}"
  printf "%-35s %-15s %s\\n" "服务名称" "状态" "说明"
  printf "%-35s %-15s %s\\n" "$(printf '─%.0s' {1..35})" "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..20})"
  for svc in ${MONITOR_SERVICES}; do
    print_unit "${svc}" yes
  done

  section "其他常见服务"
  local services=("ufw" "fail2ban" "apache2" "mysql" "postgresql" "chronyd" "ntp"
                  "google-cloud-ops-agent" "stackdriver-agent")
  for svc in "${services[@]}"; do
    print_unit "${svc}" no
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
