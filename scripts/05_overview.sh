#!/usr/bin/env bash
# 05_overview.sh —— 系统概览
# 用法: bash 05_overview.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

log() { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }
title() { echo -e "\n\e[1;34m══════════════════════════════════════\e[0m"; \
          echo -e "\e[1;36m  $*\e[0m"; \
          echo -e "\e[1;34m══════════════════════════════════════\e[0m"; }
section() { echo -e "\n\e[1;33m▶ $*\e[0m"; echo "$(printf '─%.0s' {1..40})"; }

# 用法说明（bash scripts/05_overview.sh [-h|--help]）
usage() {
  cat <<EOF
用法: bash scripts/05_overview.sh

系统概览

选项:
  -h, --help   显示本帮助并退出
EOF
}

# 参数解析：仅支持 -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ─── 1. 系统概览 ──────────────────────────────────────────────────────────────
cmd_overview() {
  title "系统概览"

  section "主机信息"
  echo "主机名:       $(hostname -f 2>/dev/null || hostname)"
  echo "操作系统:     $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
  echo "内核版本:     $(uname -r)"
  echo "系统架构:     $(uname -m)"
  echo "当前时间:     $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "启动时间:     $(uptime -s 2>/dev/null || who -b | awk '{print $3, $4}')"
  echo "运行时长:     $(uptime -p 2>/dev/null || uptime | awk -F',' '{print $1}' | awk '{print $3, $4}')"

  section "云环境元数据（自动识别 GCP / Azure）"
  # 探测函数：向给定 URL 发元数据请求，成功且返回非空内容才输出，否则静默失败。
  # 统一加硬超时（--max-time），避免沙箱/防火墙静默丢包时 curl 挂起或误判成功。
  _probe() { curl -fsS --max-time 3 -H "$1" "$2" 2>/dev/null; }

  # NAT 出口公网 IP（仅在云元数据未绑定独立公网 IP 时兜底使用）。
  # 注意：这是 Azure/GCP 出站 NAT 的共享出口 IP，并非绑在该 VM 网卡上的 PIP。
  _nat_ip() {
    local ip
    ip=$(curl -sf -m 3 https://ifconfig.me 2>/dev/null) || ip=$(curl -sf -m 3 https://api.ipify.org 2>/dev/null) || return 1
    [[ -n "$ip" ]] && echo "$ip"
  }

  # GCP 元数据服务（metadata.google.internal，需 Metadata-Flavor 头）
  if _probe "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/id" >/dev/null; then
    local murl="http://metadata.google.internal/computeMetadata/v1"
    _meta() { _probe "Metadata-Flavor: Google" "${murl}/$1"; }
    echo "云厂商:       GCP (Google Cloud)"
    echo "实例 ID:      $(_meta instance/id)"
    echo "机器类型:     $(_meta instance/machine-type | awk -F/ '{print $NF}')"
    echo "可用区:       $(_meta instance/zone | awk -F/ '{print $NF}')"
    echo "外部 IP:      $(_meta instance/network-interfaces/0/access-configs/0/external-ip || _nat_ip || echo '无（无公网 IP 绑定）')"
    echo "内部 IP:      $(_meta instance/network-interfaces/0/ip)"
    echo "项目 ID:      $(_meta project/project-id)"
  # Azure IMDS（169.254.169.254，需 Metadata: true 头 + API 版本）。
  # 注意：Azure 此 API 版本下 format=text 仅返回目录树（compute/ network/），
  # 不会返回 key=value，因此改用默认 JSON + python3 解析（最稳）。
  # 仅当 JSON 成功解析且含 compute/subscriptionId 才认作 Azure，否则降级。
  elif local az_json; az_json=$(_probe "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01") \
       && command -v python3 &>/dev/null \
       && echo "$az_json" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'compute' in d and 'subscriptionId' in d['compute']" 2>/dev/null; then
    echo "云厂商:       Azure"
    # 提取字段到 bash 变量（python 内不直接调用 _nat_ip）
    local az_name az_size az_loc az_rg az_sub az_priv az_pub
    az_name=$(echo "$az_json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["compute"].get("name","") or "")')
    az_size=$(echo "$az_json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["compute"].get("vmSize","") or "")')
    az_loc=$(echo "$az_json"  | python3 -c 'import sys,json;print(json.load(sys.stdin)["compute"].get("location","") or "")')
    az_rg=$(echo "$az_json"   | python3 -c 'import sys,json;print(json.load(sys.stdin)["compute"].get("resourceGroupName","") or "")')
    az_sub=$(echo "$az_json"  | python3 -c 'import sys,json;print(json.load(sys.stdin)["compute"].get("subscriptionId","") or "")')
    az_priv=$(echo "$az_json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["network"]["interface"][0]["ipv4"]["ipAddress"][0].get("privateIpAddress","") or "")')
    az_pub=$(echo "$az_json"  | python3 -c 'import sys,json;print(json.load(sys.stdin)["network"]["interface"][0]["ipv4"]["ipAddress"][0].get("publicIpAddress","") or "")')
    echo "VM 名称:      $az_name"
    echo "VM 大小:      $az_size"
    echo "位置:         $az_loc"
    echo "资源组:       $az_rg"
    echo "订阅 ID:      $az_sub"
    echo "内部 IP:      $az_priv"
    if [[ -n "$az_pub" ]]; then
      echo "外部 IP:      $az_pub"
    else
      echo "外部 IP:      未绑定 PIP（NAT 出口: $(_nat_ip)）"
    fi
  else
    warn "未检测到 GCP / Azure 元数据服务（可能不在云实例上）"
    echo "外部 IP:      $(curl -sf -m 3 https://ifconfig.me || echo '获取失败')"
    echo "内部 IP:      $(hostname -I | awk '{print $1}')"
  fi
}

# 主入口
cmd_overview