#!/usr/bin/env bash
# 03_monitor.sh —— 系统监控/健康检查，可加入 cron 定时执行
# 用法: bash 03_monitor.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

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

# systemd 服务存活检查
for svc in ${MONITOR_SERVICES}; do
  if ! systemctl is-active --quiet "${svc}"; then
    ALERTS+=("服务异常: ${svc} 未运行")
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
