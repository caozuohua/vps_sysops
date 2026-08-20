#!/usr/bin/env bash
# ops.sh —— VPS 运维工具总入口（模块化版）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config/ops.conf"

# 颜色与样式
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()   { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
title() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════${RESET}"; \
          echo -e "${BOLD}${CYAN}  $*${RESET}"; \
          echo -e "${BOLD}${BLUE}══════════════════════════════════════${RESET}"; }
section() { echo -e "\n${BOLD}${YELLOW}▶ $*${RESET}"; echo "$(printf '─%.0s' {1..40})"; }

# 主菜单
show_menu() {
    title "VPS 运维工具"
    echo "1) 基础安全加固（防火墙/fail2ban/自动更新/swap）"
    echo "2) 部署运行环境（Docker/Python/Node.js）"
    echo "3) 系统监控/健康检查（单次执行）"
    echo "4) 备份 + 日志轮转配置"
    echo "5) 查看系统概览"
    echo "6) 查看资源使用情况"
    echo "7) 查看进程信息"
    echo "8) 查看服务状态"
    echo "9) 日志分析"
    echo "10) 安全审计"
    echo "11) 网络诊断"
    echo "12) 磁盘与存储"
    echo "13) 系统更新检查"
    echo "14) 性能调优建议"
    echo "15) 生成完整报告"
    echo "16) 交互式运行所有模块"
    echo "17) x-ui/Nginx/Let’s Encrypt Web 栈"
    echo "18) Mem0 服务状态（只读）"
    if [[ "${AGENT_ENABLED}" == "true" ]]; then
        echo "19) Hermes Agent 服务管理"
    fi
    echo "0) 退出"
    echo
}

# 等待用户按键继续（用于交互式所有模块）
press_to_continue() {
    echo -e "${YELLOW}按 Enter 继续，Ctrl+C 退出...${RESET}"
    read -r
}

# 入口参数处理
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<EOF
VPS 运维工具包（模块化）— 交互式总入口

用法:
  ./ops.sh                启动交互式菜单
  ./ops.sh --help        显示本帮助并退出

模块（也可单独运行 scripts/ 下对应脚本，例如 bash scripts/07_resources.sh --help）:
  1)   基础安全加固         2)   部署运行环境       3)   系统监控/健康检查
  4)   备份 + 日志轮转     5)   系统概览           6)   资源监控
  7)   进程信息             8)   服务状态           9)   日志分析
  10)  安全审计            11)  网络诊断          12)  磁盘与存储
  13)  系统更新检查        14)  性能调优建议      15)  生成完整报告
  16)  交互式运行所有模块  0)   退出
  17)  x-ui/Nginx/Let’s Encrypt Web 栈
  18)  Mem0 服务状态（只读）
  19)  Hermes Agent 服务管理（按 profile 配置）
EOF
    exit 0
fi

while true; do
    show_menu
    read -rp "请选择: " choice
    case "$choice" in
        1)
            sudo bash "${SCRIPT_DIR}/scripts/01_harden.sh"
            ;;
        2)
            sudo bash "${SCRIPT_DIR}/scripts/02_setup_env.sh"
            ;;
        3)
            bash "${SCRIPT_DIR}/scripts/03_monitor.sh"
            ;;
        4)
            sudo bash "${SCRIPT_DIR}/scripts/04_backup.sh"
            ;;
        5)
            bash "${SCRIPT_DIR}/scripts/05_overview.sh"
            ;;
        6)
            bash "${SCRIPT_DIR}/scripts/07_resources.sh"
            ;;
        7)
            bash "${SCRIPT_DIR}/scripts/06_processes.sh"
            ;;
        8)
            bash "${SCRIPT_DIR}/scripts/08_services.sh"
            ;;
        9)
            bash "${SCRIPT_DIR}/scripts/09_logs.sh"
            ;;
        10)
            sudo bash "${SCRIPT_DIR}/scripts/10_security_audit.sh"
            ;;
        11)
            bash "${SCRIPT_DIR}/scripts/11_network.sh"
            ;;
        12)
            bash "${SCRIPT_DIR}/scripts/12_disk.sh"
            ;;
        13)
            sudo bash "${SCRIPT_DIR}/scripts/13_updates.sh"
            ;;
        14)
            bash "${SCRIPT_DIR}/scripts/15_tune.sh"
            ;;
        15)
            sudo bash "${SCRIPT_DIR}/scripts/16_report.sh"
            ;;
        16)
            # 交互式运行所有模块
            for script in 05_overview 07_resources 06_processes 08_services 09_logs 10_security_audit 11_network 12_disk 13_updates 14_web_stack 15_tune mem0; do
                if [[ "$script" == 10_security_audit || "$script" == 13_updates || "$script" == 14_web_stack || "$script" == 16_report ]]; then
                    sudo bash "${SCRIPT_DIR}/scripts/${script}.sh"
                else
                    bash "${SCRIPT_DIR}/scripts/${script}.sh"
                fi
                press_to_continue
            done
            ;;
        17)
            sudo bash "${SCRIPT_DIR}/scripts/14_web_stack.sh"
            ;;
        18)
            bash "${SCRIPT_DIR}/scripts/mem0.sh" status
            ;;
        19)
            bash "${SCRIPT_DIR}/scripts/agent_ctl.sh"
            ;;
        0)
            echo "再见！"
            exit 0
            ;;
        *)
            warn "无效选择，请重新输入。"
            ;;
    esac
done
