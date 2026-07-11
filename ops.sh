#!/usr/bin/env bash
# ops.sh —— VPS 运维工具总入口
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========== VPS 运维工具 =========="
echo "1) 基础安全加固（防火墙/fail2ban/自动更新/swap）"
echo "2) 部署运行环境（Docker/Python/Node.js）"
echo "3) 系统监控/健康检查（单次执行）"
echo "4) 备份 + 日志轮转配置"
echo "5) 全部执行（1 -> 2 -> 4，监控建议加入 cron 定时）"
echo "0) 退出"
read -rp "请选择: " choice

case "$choice" in
  1) sudo bash "${SCRIPT_DIR}/scripts/01_harden.sh" ;;
  2) sudo bash "${SCRIPT_DIR}/scripts/02_setup_env.sh" ;;
  3) bash "${SCRIPT_DIR}/scripts/03_monitor.sh" ;;
  4) sudo bash "${SCRIPT_DIR}/scripts/04_backup.sh" ;;
  5)
    sudo bash "${SCRIPT_DIR}/scripts/01_harden.sh"
    sudo bash "${SCRIPT_DIR}/scripts/02_setup_env.sh"
    sudo bash "${SCRIPT_DIR}/scripts/04_backup.sh"
    echo "提示：请将 scripts/03_monitor.sh 加入 crontab 定时执行"
    ;;
  0) exit 0 ;;
  *) echo "无效选择" ;;
esac
