#!/usr/bin/env bash
# 10_security_audit.sh —— 安全审计（防火墙 / SSH 暴破 / fail2ban / SUID / 用户 / sudo / 密钥）
# 用法: sudo bash 10_security_audit.sh
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

# 用法说明（bash scripts/10_security_audit.sh [-h|--help]）
usage() {
  cat <<EOF
用法: sudo bash scripts/10_security_audit.sh

安全审计（防火墙 / SSH 暴破 / fail2ban / SUID / 用户 / sudo / 密钥）

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 6. 安全审计 ──────────────────────────────────────────────────────────────
cmd_security() {
  title "安全审计"

  section "防火墙状态（UFW）"
  if command -v ufw &>/dev/null; then
    ufw status verbose 2>/dev/null || warn "UFW 状态查询失败（需要 root）"
  else
    warn "UFW 未安装"
  fi

  section "iptables 规则数"
  if command -v iptables &>/dev/null; then
    echo "INPUT 规则:   $(iptables -L INPUT --line-numbers 2>/dev/null | grep -c '^[0-9]' || echo 'N/A')"
    echo "OUTPUT 规则:  $(iptables -L OUTPUT --line-numbers 2>/dev/null | grep -c '^[0-9]' || echo 'N/A')"
  fi

  section "SSH 暴力破解检测（失败 IP Top 10）"
  if [[ -f /var/log/auth.log ]]; then
    grep "Failed password" /var/log/auth.log 2>/dev/null | \
      awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -10 | \
      awk '{printf "  尝试次数: %-5s  IP: %s\n", $1, $2}' || echo "无记录"
  else
    journalctl -u ssh --no-pager 2>/dev/null | grep "Failed password" | \
      awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -10 || \
      warn "无法读取认证日志"
  fi

  section "fail2ban 被封 IP"
  if command -v fail2ban-client &>/dev/null; then
    fail2ban-client status 2>/dev/null | grep "Jail list" | \
      sed 's/.*Jail list:\s*//' | tr ',' '\n' | xargs -I{} sh -c \
      'echo "── Jail: {}"; fail2ban-client status {} 2>/dev/null | grep -E "Currently banned|Total banned"' \
      2>/dev/null || warn "fail2ban 查询失败"
  else
    warn "fail2ban 未安装"
  fi

  section "SUID/SGID 文件（异常排查）"
  echo "搜索 SUID 文件（排除已知安全路径）..."
  find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | \
    grep -v -E "/usr/bin/|/usr/lib|/bin/|/sbin/" | head -20 || echo "无异常 SUID/SGID 文件"

  section "近期新增用户（/etc/passwd 排查）"
  awk -F: '$3 >= 1000 && $3 < 65534 {printf "用户: %-15s UID: %-6s Shell: %s\n", $1, $3, $7}' /etc/passwd

  section "有 sudo 权限的用户"
  grep -v '^#' /etc/sudoers 2>/dev/null | grep -v '^$' | grep -v "^Defaults" | head -20 || true
  getent group sudo wheel 2>/dev/null | awk -F: '{print "组:", $1, "成员:", $4}'

  section "SSH 密钥认证用户"
  find /home /root -name "authorized_keys" 2>/dev/null | while read -r f; do
    echo "文件: $f ($(wc -l < "$f") 个公钥)"
  done
}

# 主入口
cmd_security
