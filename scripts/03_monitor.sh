#!/usr/bin/env bash
# 03_monitor.sh —— 系统监控/健康检查，可加入 cron 定时执行
# 用法: bash 03_monitor.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

# 用法说明（bash scripts/03_monitor.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/03_monitor.sh

可选环境变量:
  VPS_PROFILE=gcp|azure   显式选择主机配置（已知主机会按 hostname 自动选择）

系统监控/健康检查，可加入 cron 定时执行

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

HOSTNAME_STR=$(hostname)
ALERTS=()

# CPU：用 1 分钟平均负载 / 核心数 近似算作使用率
CPU_CORES=$(nproc)
LOAD1=$(awk '{print $1}' /proc/loadavg)
CPU_PCT=$(awk -v l="$LOAD1" -v c="$CPU_CORES" 'BEGIN{printf "%.0f", (l/c)*100}')
if (( CPU_PCT > CPU_THRESHOLD )); then
  ALERTS+=("CPU 负载过高: ${CPU_PCT}% (阈值 ${CPU_THRESHOLD}%)")
fi

# 内存
MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
if (( MEM_PCT > MEM_THRESHOLD )); then
  ALERTS+=("内存使用过高: ${MEM_PCT}% (阈值 ${MEM_THRESHOLD}%)")
fi

# 磁盘（根分区）
DISK_PCT=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
if (( DISK_PCT > DISK_THRESHOLD )); then
  ALERTS+=("磁盘使用过高: ${DISK_PCT}% (阈值 ${DISK_THRESHOLD}%)")
fi

# systemd 服务存活检查。先查系统级，再检查 MONITOR_USER 的用户级服务。
user_unit_active() {
  local unit="$1"
  local target_user="${MONITOR_USER:-$(id -un)}"
  local target_uid
  target_uid=$(id -u "${target_user}" 2>/dev/null) || return 1
  [[ -d "/run/user/${target_uid}" ]] || return 1

  if [[ "$(id -un)" == "${target_user}" ]]; then
    XDG_RUNTIME_DIR="/run/user/${target_uid}" systemctl --user is-active --quiet "${unit}" 2>/dev/null
  elif [[ $EUID -eq 0 ]] && command -v runuser >/dev/null 2>&1; then
    runuser -u "${target_user}" -- env XDG_RUNTIME_DIR="/run/user/${target_uid}" \
      systemctl --user is-active --quiet "${unit}" 2>/dev/null
  else
    return 1
  fi
}

for svc in ${MONITOR_SERVICES}; do
  unit="${svc}"
  [[ "${unit}" == *.* ]] || unit="${unit}.service"
  if systemctl is-active --quiet "${unit}" 2>/dev/null; then
    : # 系统级运行中
  elif user_unit_active "${unit}"; then
    : # MONITOR_USER 的用户级服务运行中
  else
    ALERTS+=("服务异常: ${unit} 未运行（system / ${MONITOR_USER:-current user} user 均未激活）")
  fi
done

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
STATUS_LINE="[$TIMESTAMP] ${HOSTNAME_STR} | CPU:${CPU_PCT}% MEM:${MEM_PCT}% DISK:${DISK_PCT}%"
echo "$STATUS_LINE"

if [[ ${#ALERTS[@]} -gt 0 ]]; then
  echo "发现异常:"
  printf '  - %s\n' "${ALERTS[@]}"

  if [[ -n "${FEISHU_WEBHOOK}" ]]; then
    MSG="VPS 告警 [${HOSTNAME_STR}]\n${STATUS_LINE}\n$(printf '%s\\n' "${ALERTS[@]}")"
    curl -s -X POST "${FEISHU_WEBHOOK}" \
      -H 'Content-Type: application/json' \
      -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"${MSG}\"}}" > /dev/null || true
  fi
  exit 1
else
  echo "状态正常"
  exit 0
fi
