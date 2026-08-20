#!/usr/bin/env bash
# 16_report.sh —— 生成全量运维报告（汇聚各只读模块，输出到 REPORT_DIR）
# 用法: sudo bash 16_report.sh   （security/updates 子项需 root）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

# 用法说明（bash scripts/16_report.sh [-h|--help]）
usage() {
  cat <<EOF
用法: sudo bash scripts/16_report.sh

生成全量运维报告（汇聚各只读模块，输出到 REPORT_DIR）

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }
title() { echo -e "\n\e[1;34m═══════════════════════════════════════\e[0m"; \
          echo -e "\e[1;36m  $*\e[0m"; \
          echo -e "\e[1;34m═══════════════════════════════════════\e[0m"; }
section() { echo -e "\n\e[1;33m▶ $*\e[0m"; echo "$(printf '─%.0s' {1..40})"; }

# REPORT_DIR 来自 config/ops.conf；兜底默认 /tmp/vps-ops-reports
REPORT_DIR="${REPORT_DIR:-/tmp/vps-ops-reports}"
mkdir -p "$REPORT_DIR"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
REPORT_FILE="${REPORT_DIR}/report_${TIMESTAMP}.txt"

run_module() {
  local name="$1" script="$2" root="$3"
  {
    echo ""
    echo "════════════════════════════════════════════════"
    echo "  $name"
    echo "════════════════════════════════════════════════"
    if [[ "$root" == "yes" && $EUID -ne 0 ]]; then
      echo "[SKIP] 需要 root 权限，以 sudo 重新运行本脚本"
    else
      bash "${SCRIPT_DIR}/${script}.sh" 2>&1 || echo "[WARN] ${script} 执行出错（退出码 $?）"
    fi
  } 2>&1 | tee -a "$REPORT_FILE"
}

cmd_report() {
  title "生成全量运维报告 → ${REPORT_FILE}"
  echo "报告生成时间: $(date)" | tee "$REPORT_FILE"
  echo "主机名:       $(hostname)" | tee -a "$REPORT_FILE"
  echo "" | tee -a "$REPORT_FILE"

  run_module "系统概览"       05_overview      no
  run_module "资源监控"       07_resources     no
  run_module "进程管理"       06_processes     no
  run_module "服务管理"       08_services      no
  run_module "日志分析"       09_logs          no
  run_module "网络诊断"       11_network       no
  run_module "磁盘与存储"     12_disk          no
  run_module "性能调优建议"   15_tune          no
  run_module "安全审计"       10_security_audit yes
 run_module "系统更新检查"   13_updates       yes
  run_module "Web 栈状态"      14_web_stack     yes

  {
    echo ""
    echo "════════════════════════════════════════════════"
    echo "  Mem0 服务状态"
    echo "════════════════════════════════════════════════"
    bash "${SCRIPT_DIR}/mem0.sh" status 2>&1 || echo "[WARN] mem0 status 执行出错（退出码 $?）"
  } 2>&1 | tee -a "$REPORT_FILE"

  echo ""
  log "✅ 全量报告已保存至: ${REPORT_FILE}"
  echo "   大小: $(ls -lh "$REPORT_FILE" | awk '{print $5}')"
}

# 主入口
cmd_report
