#!/usr/bin/env bash
# agent_ctl.sh —— 将 GCP Hermes Lite agent-ctl 接入 ops 菜单
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${AGENT_CTL:-}" ]]; then
  AGENT_CTL="${AGENT_CTL}"
elif [[ -x "${SCRIPT_DIR}/agent-ctl" ]]; then
  AGENT_CTL="${SCRIPT_DIR}/agent-ctl"
else
  AGENT_CTL="agent-ctl"
fi

usage() {
  cat <<EOF
用法: bash scripts/agent_ctl.sh [命令] [参数]

命令:
  menu                              打开 Agent 服务管理菜单（默认）
  status                            查看 hermes-gateway.service 状态
  start|stop|restart                启停或重启 Agent 服务
  log [行数]                        查看最近日志
  logf                              跟踪实时日志（Ctrl+C 退出）
  venv                              查看 Hermes Lite Python 环境
  help                              显示 agent-ctl 原生帮助

后端: ${AGENT_CTL}
EOF
}

resolve_agent_ctl() {
  if [[ "${AGENT_CTL}" == */* ]]; then
    [[ -x "${AGENT_CTL}" ]] || { echo "找不到 agent-ctl: ${AGENT_CTL}" >&2; return 1; }
  else
    command -v "${AGENT_CTL}" >/dev/null 2>&1 || {
      echo "当前主机未安装 agent-ctl（此入口主要用于 GCP Hermes Lite）" >&2
      return 1
    }
  fi
}

run_agent_ctl() {
  resolve_agent_ctl
  "${AGENT_CTL}" "$@"
}

menu() {
  while true; do
    cat <<'EOF'

Hermes Agent 服务管理
─────────────────────
1) 查看状态
2) 启动服务
3) 停止服务
4) 重启服务
5) 查看最近日志（50 行）
6) 跟踪实时日志
7) 检查 Python 虚拟环境
8) 查看 agent-ctl 帮助
0) 返回上级菜单
EOF
    read -rp "请选择: " choice
    case "${choice}" in
      1) run_agent_ctl status || true ;;
      2) run_agent_ctl start || true ;;
      3) run_agent_ctl stop || true ;;
      4) run_agent_ctl restart || true ;;
      5) run_agent_ctl log 50 || true ;;
      6) run_agent_ctl logf || true ;;
      7) run_agent_ctl venv || true ;;
      8) run_agent_ctl help || true ;;
      0) return 0 ;;
      *) echo "无效选择" >&2 ;;
    esac
  done
}

case "${1:-menu}" in
  menu) menu ;;
  -h|--help) usage ;;
  status|start|stop|restart|log|logf|venv|help)
    shift || true
    run_agent_ctl "$@"
    ;;
  *)
    echo "未知命令: ${1}" >&2
    usage >&2
    exit 2
    ;;
esac
