#!/usr/bin/env bash
# sync_fail2ban_to_ufw.sh —— 将 fail2ban 当前封禁的 IP 同步进 UFW（双向：封新增 + 清过期）
#
# 背景：本环境（受限沙箱）fail2ban 的 action 执行机制整体失效——ban 事件能产生，
#       但 actionban 命令从不执行（action 执行器未正常启动，已用 action 调试日志确认）。
#       因此用本脚本读取 fail2ban 『当前实际封禁列表』，自动调用 ufw deny 补上真实封禁，
#       并在 fail2ban 解封后清理对应 UFW 规则。
#
# 安全设计：
#   1. 白名单：回环 / 私有网段 / 本机公网 IP / 管理员 IP / UFW 已 allow 的 IP 永不封（防误锁自己）
#   2. 双向同步：封 fail2ban 当前仍 ban 的 IP；清 UFW 里已不在 fail2ban 封禁列表的 f2b-auto 规则
#      （跟随 fail2ban 生命周期，不无限膨胀）
#
# 用法: sudo bash scripts/sync_fail2ban_to_ufw.sh
# 触发: systemd timer 每 30s 触发（/etc/systemd/system/failsync.timer）

set -uo pipefail

# 用法说明（sudo bash scripts/sync_fail2ban_to_ufw.sh [-h|--help]）
usage() {
  cat <<EOF
用法: sudo bash scripts/sync_fail2ban_to_ufw.sh

将 Fail2Ban 当前封禁的 IP 同步进 UFW（双向：封新增 + 清过期）。
由 systemd timer 每 30s 触发，一般无需手动运行。

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "请使用 sudo 或 root 权限运行此脚本" >&2
  exit 1
fi

exec 9>/run/lock/vps-sysops-failsync.lock
flock -n 9 || exit 0

UFW=/usr/sbin/ufw
COMMENT="f2b-auto"
JAILS="sshd recidive"

log() { echo "[$(date '+%F %T')] $*"; }

[[ -x "$UFW" ]] || { log "ERROR: ufw 不存在或未执行"; exit 1; }

# ─── 白名单（永不封禁）──────────────────────────────────────────────────────
SELF_IP="$(curl -sf -m 5 https://ifconfig.me || true)"
ADMIN_IPS="$(last -i -n 20 2>/dev/null | grep -vE 'reboot|wtmp|still' | awk '{print $3}' | grep -E '^[0-9.]+$' | sort -u || true)"
ALLOWED_IPS="$("$UFW" status 2>/dev/null | grep -iE 'ALLOW' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u || true)"

is_whitelisted() {
  local ip="$1"
  [[ "$ip" == "127.0.0.1" || "$ip" == "::1" ]] && return 0
  [[ "$ip" =~ ^10\. ]] && return 0
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && return 0
  [[ "$ip" =~ ^192\.168\. ]] && return 0
  [[ "$ip" =~ ^169\.254\. ]] && return 0
  [[ "$ip" =~ ^fd ]] && return 0
  [[ "$ip" == "$SELF_IP" ]] && return 0
  for w in $ADMIN_IPS $ALLOWED_IPS; do
    [[ "$ip" == "$w" ]] && return 0
  done
  return 1
}

# ─── 取 fail2ban 当前实际封禁的 IP（来自各 jail 的 Banned IP list）──────────
BANNED_SET=""
for j in $JAILS; do
  ips="$(fail2ban-client status "$j" 2>/dev/null | sed -n '/Banned IP list/,/^$/p' | grep -oE '([0-9a-fA-F:.]+)' | grep -E '^[0-9]' | sort -u)"
  BANNED_SET+=" $ips"
done
BANNED_SET="$(echo "$BANNED_SET" | tr ' ' '\n' | sort -u | grep -v '^$')"

# ─── 1. 封禁：fail2ban 当前 ban 但 UFW 还没有的 IP ─────────────────────────
added=0
while IFS= read -r ip; do
  [[ -z "$ip" ]] && continue
  is_whitelisted "$ip" && { log "SKIP (whitelist): $ip"; continue; }
  if "$UFW" status 2>/dev/null | grep -q "$ip.*$COMMENT"; then
    continue
  fi
  if "$UFW" deny from "$ip" to any comment "$COMMENT" >/dev/null 2>&1; then
    log "DENY: $ip"
    added=$((added+1))
  else
    log "FAIL ufw deny: $ip"
  fi
done <<< "$BANNED_SET"

# ─── 2. 清理：UFW 里 f2b-auto 规则但已不在 fail2ban 封禁列表的 IP ───────────
mapfile -t UFW_F2B < <("$UFW" status numbered 2>/dev/null \
  | grep "$COMMENT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

removed=0
for ip in "${UFW_F2B[@]:-}"; do
  [[ -z "$ip" ]] && continue
  if ! echo "$BANNED_SET" | grep -qx "$ip"; then
    if "$UFW" delete deny from "$ip" to any >/dev/null 2>&1; then
      log "UNBAN (expired in f2b): $ip"
      removed=$((removed+1))
    fi
  fi
done

[[ $added -eq 0 && $removed -eq 0 ]] && log "无变更"
exit 0
