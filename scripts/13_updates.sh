#!/usr/bin/env bash
# 13_updates.sh —— 系统更新检查 & 安全补丁（部分子项需 root）
# 用法: sudo bash 13_updates.sh  （AUTO_UPDATE=true 可自动安装安全更新）
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

require_root() {
  [[ $EUID -eq 0 ]] || { error "此操作需要 root 权限，请使用 sudo 运行"; exit 1; }
}

# 用法说明（bash scripts/13_updates.sh [-h|--help]）
usage() {
  cat <<EOF
用法: sudo bash scripts/13_updates.sh

系统更新检查 & 安全补丁（部分子项需 root）

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 9. 系统更新 ──────────────────────────────────────────────────────────────
cmd_updates() {
  title "系统更新"
  require_root

  section "可用更新"
  apt update -qq 2>/dev/null
  local upgradable
  upgradable=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
  echo "可更新包数量: ${upgradable}"

  section "安全补丁"
  apt list --upgradable 2>/dev/null | grep -i security | head -20 || echo "无安全补丁待更新"

  section "已安装包统计"
  echo "已安装包总数: $(dpkg -l | grep -c '^ii')"
  echo "手动安装包数: $(apt-mark showmanual 2>/dev/null | wc -l)"

  section "最近安装/升级历史（最近 20 条）"
  grep -E "install|upgrade" /var/log/dpkg.log 2>/dev/null | tail -20 || \
    zcat /var/log/dpkg.log.*.gz 2>/dev/null | grep -E "install|upgrade" | tail -20

  if [[ "${AUTO_UPDATE:-false}" == "true" ]]; then
    section "执行安全更新"
    warn "正在安装安全更新..."
    apt-get -y -q upgrade --with-new-pkgs 2>&1 | tail -5
    log "安全更新完成"
  else
    warn "跳过自动更新。如需执行：AUTO_UPDATE=true bash scripts/13_updates.sh"
  fi
}

# 主入口
cmd_updates
