#!/usr/bin/env bash
# 02_setup_env.sh —— 部署运行环境: Docker / Python / Node.js / 常用工具
# 用法: sudo bash 02_setup_env.sh
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "请使用 sudo 或 root 权限运行此脚本" >&2
  exit 1
fi

log "==== 部署运行环境 ===="

apt-get update -y
apt-get install -y ca-certificates curl wget gnupg git htop tmux jq unzip build-essential

# ---- Docker ----
if ! command -v docker &>/dev/null; then
  log "安装 Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

# 用法说明（bash scripts/02_setup_env.sh [-h|--help]）
usage() {
  cat <<EOF
用法: sudo bash scripts/02_setup_env.sh

部署运行环境: Docker / Python / Node.js / 常用工具

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  log "Docker 版本: $(docker --version)"
else
  log "Docker 已安装，跳过 ($(docker --version))"
fi

# 将当前 sudo 调用用户加入 docker 组，免 sudo 使用 docker
if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "${SUDO_USER}"
  log "已将用户 ${SUDO_USER} 加入 docker 组（需重新登录生效）"
fi

# ---- Python ----
if ! command -v python3 &>/dev/null; then
  log "安装 Python3..."
  apt-get install -y python3 python3-venv python3-pip
else
  log "Python3 已安装: $(python3 --version)"
  apt-get install -y python3-venv python3-pip
fi

# ---- Node.js (LTS) ----
if ! command -v node &>/dev/null; then
  log "安装 Node.js LTS..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt-get install -y nodejs
  log "Node 版本: $(node --version), npm: $(npm --version)"
else
  log "Node.js 已安装: $(node --version)"
fi

log "==== 运行环境部署完成 ===="
