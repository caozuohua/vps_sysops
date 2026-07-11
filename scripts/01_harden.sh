#!/usr/bin/env bash
# 01_harden.sh —— 基础安全加固
# 用法: sudo bash 01_harden.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

# 用法说明（bash scripts/01_harden.sh [-h|--help]）
usage() {
  cat <<EOF
用法: sudo bash scripts/01_harden.sh

基础安全加固

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
LOG_FILE="/var/log/vps-ops-harden.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

if [[ $EUID -ne 0 ]]; then
  echo "请使用 sudo 或 root 权限运行此脚本" >&2
  exit 1
fi

log "==== 开始基础安全加固 ===="

log "更新软件包索引与已安装包..."
apt-get update -y
apt-get upgrade -y

log "安装 ufw / fail2ban / unattended-upgrades ..."
apt-get install -y ufw fail2ban unattended-upgrades

log "配置 UFW 防火墙 (放行 SSH 端口 ${SSH_PORT})..."
ufw allow "${SSH_PORT}/tcp"
if [[ -n "${EXTRA_ALLOW_PORTS}" ]]; then
  IFS=',' read -ra PORTS <<< "${EXTRA_ALLOW_PORTS}"
  for p in "${PORTS[@]}"; do
    log "放行端口 ${p}"
    ufw allow "${p}/tcp"
  done
fi
ufw --force enable
ufw status verbose | tee -a "$LOG_FILE"

log "配置 fail2ban（针对 sshd）..."
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 5
bantime = 3600
findtime = 600
EOF
systemctl enable fail2ban
systemctl restart fail2ban

log "启用自动安全更新 (unattended-upgrades) ..."
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

if ! swapon --show | grep -q .; then
  log "未检测到 swap，创建 2G swap 文件..."
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
else
  log "已存在 swap，跳过创建"
fi

log "当前 SSH 关键配置："
grep -E '^(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config 2>/dev/null || true

log "==== 提示：未自动禁用 root/密码登录，避免误操作锁死 ===="
log "如需禁用，请先确认已有可用 SSH 密钥登录的 sudo 用户，然后手动编辑"
log "  /etc/ssh/sshd_config"
log "设置 PermitRootLogin no 与 PasswordAuthentication no，"
log "并执行: systemctl restart sshd"

log "==== 基础安全加固完成 ===="
