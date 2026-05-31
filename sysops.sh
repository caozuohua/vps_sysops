#!/usr/bin/env bash
# =============================================================================
# sysops.sh — GCP Ubuntu VPS 全面系统运维脚本
# 支持系统信息、资源监控、服务管理、日志分析、安全审计、备份、性能优化
# 用法: bash sysops.sh [选项]
# =============================================================================

set -euo pipefail

# ─── 颜色 & 样式 ──────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m'; RESET='\033[0m'

# ─── 全局配置 ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/sysops"
REPORT_DIR="/tmp/sysops_reports"
BACKUP_DIR="/var/backups/sysops"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_FILE="${REPORT_DIR}/report_${TIMESTAMP}.txt"
SCRIPT_VERSION="2.0.0"

# ─── 工具函数 ─────────────────────────────────────────────────────────────────
log()     { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
title()   { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${BLUE}══════════════════════════════════════${RESET}"; }
section() { echo -e "\n${BOLD}${YELLOW}▶ $*${RESET}"; echo "$(printf '─%.0s' {1..40})"; }

require_root() {
  [[ $EUID -eq 0 ]] || { error "此操作需要 root 权限，请使用 sudo 运行"; exit 1; }
}

init_dirs() {
  mkdir -p "$LOG_DIR" "$REPORT_DIR" "$BACKUP_DIR"
}

# 记录输出到报告文件（同时显示在终端）
tee_report() {
  init_dirs
  "$@" 2>&1 | tee -a "$REPORT_FILE"
}

# ─── 1. 系统概览 ──────────────────────────────────────────────────────────────
cmd_overview() {
  title "系统概览"

  section "主机信息"
  echo "主机名:       $(hostname -f 2>/dev/null || hostname)"
  echo "操作系统:     $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
  echo "内核版本:     $(uname -r)"
  echo "系统架构:     $(uname -m)"
  echo "当前时间:     $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "启动时间:     $(uptime -s 2>/dev/null || who -b | awk '{print $3, $4}')"
  echo "运行时长:     $(uptime -p 2>/dev/null || uptime | awk -F',' '{print $1}' | awk '{print $3, $4}')"

  section "GCP 元数据"
  local murl="http://metadata.google.internal/computeMetadata/v1"
  local mcurl="curl -sf -m 2 -H Metadata-Flavor: Google"
  if curl -sf -m 2 -H "Metadata-Flavor: Google" "${murl}/instance/id" &>/dev/null; then
    _meta() { curl -sf -m 2 -H "Metadata-Flavor: Google" "${murl}/$1"; }
    echo "实例 ID:      $(_meta instance/id)"
    echo "机器类型:     $(_meta instance/machine-type | awk -F/ '{print $NF}')"
    echo "可用区:       $(_meta instance/zone | awk -F/ '{print $NF}')"
    echo "外部 IP:      $(_meta instance/network-interfaces/0/access-configs/0/external-ip || echo '无')"
    echo "内部 IP:      $(_meta instance/network-interfaces/0/ip)"
    echo "项目 ID:      $(_meta project/project-id)"
  else
    warn "未检测到 GCP 元数据服务（可能不在 GCE 实例上）"
    echo "外部 IP:      $(curl -sf -m 3 https://ifconfig.me || echo '获取失败')"
    echo "内部 IP:      $(hostname -I | awk '{print $1}')"
  fi
}

# ─── 2. 资源监控 ──────────────────────────────────────────────────────────────
cmd_resources() {
  title "资源监控"

  section "CPU"
  echo "处理器型号:   $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
  echo "物理核心数:   $(grep -c '^processor' /proc/cpuinfo)"
  local idle
  idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | tr -d '%id,')
  echo "CPU 使用率:   $(echo "100 - ${idle:-0}" | bc 2>/dev/null || echo 'N/A')%"
  echo "负载均衡:     $(cat /proc/loadavg | awk '{print "1min=" $1, "5min=" $2, "15min=" $3}')"

  section "内存"
  free -h | awk '
    NR==1 {printf "%-12s %8s %8s %8s %8s\n", "", $1, $2, $3, $4}
    NR==2 {printf "%-12s %8s %8s %8s %8s\n", "RAM:", $2, $3, $4, $6}
    NR==3 {printf "%-12s %8s %8s %8s\n", "Swap:", $2, $3, $4}
  '
  local mem_used mem_total mem_pct
  mem_used=$(free -m | awk 'NR==2{print $3}')
  mem_total=$(free -m | awk 'NR==2{print $2}')
  mem_pct=$(awk "BEGIN{printf \"%.1f\", ${mem_used}/${mem_total}*100}" 2>/dev/null || echo 0)
  echo "内存使用率:   ${mem_pct}%"
  [[ $(echo "$mem_pct > 85" | bc 2>/dev/null) -eq 1 ]] && warn "内存使用率超过 85%，请关注！"

  section "磁盘空间"
  df -hT | grep -v tmpfs | grep -v devtmpfs | \
    awk 'NR==1{print} NR>1{
      pct=$6; gsub(/%/,"",pct);
      if(pct+0 >= 90) printf "\033[0;31m%s\033[0m\n", $0
      else if(pct+0 >= 75) printf "\033[1;33m%s\033[0m\n", $0
      else print
    }'

  section "磁盘 I/O（iostat，若可用）"
  if command -v iostat &>/dev/null; then
    iostat -x 1 1 | grep -v '^$' | tail -n +3
  else
    warn "iostat 未安装，跳过（安装：apt install sysstat）"
  fi

  section "网络接口"
  ip -br addr show | grep -v '^lo'
  echo ""
  if command -v ss &>/dev/null; then
    echo "TCP 连接状态统计:"
    ss -s | grep -E "TCP|estab|closed|time-wait"
  fi
}

# ─── 3. 进程管理 ──────────────────────────────────────────────────────────────
cmd_processes() {
  title "进程管理"

  section "CPU 占用 Top 10"
  ps aux --sort=-%cpu | head -11 | \
    awk 'NR==1{printf "%-8s %-6s %-5s %-5s %-10s %s\n", "USER", "PID", "%CPU", "%MEM", "STATUS", "COMMAND"}
         NR>1{printf "%-8s %-6s %-5s %-5s %-10s %s\n", $1, $2, $3, $4, $8, substr($0, index($0,$11), 40)}'

  section "内存占用 Top 10"
  ps aux --sort=-%mem | head -11 | \
    awk 'NR==1{printf "%-8s %-6s %-5s %-5s %-10s %s\n", "USER", "PID", "%CPU", "%MEM", "STATUS", "COMMAND"}
         NR>1{printf "%-8s %-6s %-5s %-5s %-10s %s\n", $1, $2, $3, $4, $8, substr($0, index($0,$11), 40)}'

  section "僵尸进程检查"
  local zombies
  zombies=$(ps aux | awk '$8=="Z"' | wc -l)
  if [[ $zombies -gt 0 ]]; then
    warn "发现 ${zombies} 个僵尸进程："
    ps aux | awk 'NR==1 || $8=="Z"'
  else
    log "无僵尸进程"
  fi

  section "系统进程总数"
  echo "运行中: $(ps aux | grep -c ' R ')"
  echo "休眠中: $(ps aux | grep -c ' S ')"
  echo "总计:   $(ps aux | wc -l)"
}

# ─── 4. 服务管理 ──────────────────────────────────────────────────────────────
cmd_services() {
  title "服务管理"

  section "关键服务状态"
  local services=("ssh" "ufw" "fail2ban" "nginx" "apache2" "mysql" "postgresql"
                  "docker" "google-cloud-ops-agent" "stackdriver-agent" "chronyd" "ntp")
  printf "%-35s %-15s %s\n" "服务名称" "状态" "说明"
  printf "%-35s %-15s %s\n" "$(printf '─%.0s' {1..35})" "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..20})"
  for svc in "${services[@]}"; do
    if systemctl list-units --type=service --all | grep -q "${svc}.service"; then
      local status
      status=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
      local color="${GREEN}"
      [[ "$status" != "active" ]] && color="${RED}"
      local enabled
      enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "N/A")
      printf "%-35s ${color}%-15s${RESET} %s\n" "$svc" "$status" "enabled=$enabled"
    fi
  done

  section "最近启动/停止的服务（最近 10 条）"
  journalctl --no-pager -n 200 --since "24 hours ago" -o short-iso 2>/dev/null | \
    grep -E "Started|Stopped|Failed" | tail -10 || \
    warn "journalctl 查询失败，请以 root 运行"

  section "监听端口"
  ss -tlnp 2>/dev/null | grep -v '127.0.0.53' || netstat -tlnp 2>/dev/null || warn "ss/netstat 不可用"
}

# ─── 5. 日志分析 ──────────────────────────────────────────────────────────────
cmd_logs() {
  title "日志分析"

  section "系统错误（最近 24h，syslog）"
  if [[ -f /var/log/syslog ]]; then
    grep -i "error\|critical\|panic\|oops" /var/log/syslog | \
      grep "$(date '+%b %_d')\|$(date -d '1 day ago' '+%b %_d' 2>/dev/null)" 2>/dev/null | \
      tail -20 || echo "无错误日志"
  else
    journalctl -p err --since "24 hours ago" --no-pager 2>/dev/null | tail -20 || \
      warn "日志读取失败"
  fi

  section "认证失败（最近 50 条）"
  if [[ -f /var/log/auth.log ]]; then
    grep -i "failed\|invalid\|authentication failure" /var/log/auth.log | tail -20 || \
      echo "无认证失败记录"
  else
    journalctl -u ssh --since "24 hours ago" --no-pager 2>/dev/null | \
      grep -i "failed\|invalid" | tail -20 || warn "SSH 日志读取失败"
  fi

  section "内核 OOM 事件"
  if dmesg 2>/dev/null | grep -qi "out of memory\|oom-killer"; then
    warn "检测到 OOM 事件："
    dmesg 2>/dev/null | grep -i "out of memory\|oom-killer" | tail -10
  else
    log "无 OOM 事件"
  fi

  section "磁盘错误"
  dmesg 2>/dev/null | grep -iE "I/O error|disk|ext4|filesystem" | tail -10 || echo "无磁盘错误"

  section "大日志文件 Top 10（/var/log）"
  find /var/log -type f -name "*.log" -o -name "*.log.*" 2>/dev/null | \
    xargs ls -lh 2>/dev/null | sort -k5 -rh | head -10 | \
    awk '{printf "%-10s %s\n", $5, $9}'
}

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
  find /home /root -name "authorized_keys" 2>/dev/null | while read f; do
    echo "文件: $f ($(wc -l < "$f") 个公钥)"
  done
}

# ─── 7. 网络诊断 ──────────────────────────────────────────────────────────────
cmd_network() {
  title "网络诊断"

  section "网络接口详情"
  ip addr show | grep -E "^[0-9]+:|inet " | grep -v '127.0.0.1'

  section "路由表"
  ip route show

  section "DNS 解析"
  echo "DNS 服务器: $(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')"
  echo -n "解析测试 (google.com): "
  dig +short google.com 2>/dev/null | head -1 || nslookup google.com 2>/dev/null | grep Address | tail -1 || echo "失败"

  section "GCP 连接性测试"
  local endpoints=("metadata.google.internal:80" "storage.googleapis.com:443" "compute.googleapis.com:443")
  for ep in "${endpoints[@]}"; do
    local host="${ep%%:*}"
    local port="${ep##*:}"
    if timeout 3 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
      echo -e "${GREEN}✓${RESET} ${ep}"
    else
      echo -e "${RED}✗${RESET} ${ep} (不可达)"
    fi
  done

  section "活跃网络连接 Top 5（远程 IP）"
  ss -tn state established 2>/dev/null | awk 'NR>1{print $5}' | \
    cut -d: -f1 | sort | uniq -c | sort -rn | head -5 || true

  section "网络统计"
  if [[ -f /proc/net/dev ]]; then
    awk 'NR>2 && $1!="lo:" {
      gsub(/:/, "", $1)
      printf "%-12s RX: %-15s TX: %-15s\n", $1,
        (($2/1024/1024 > 1) ? sprintf("%.1f MB", $2/1024/1024) : sprintf("%.1f KB", $2/1024)),
        (($10/1024/1024 > 1) ? sprintf("%.1f MB", $10/1024/1024) : sprintf("%.1f KB", $10/1024))
    }' /proc/net/dev
  fi
}

# ─── 8. 磁盘与存储 ────────────────────────────────────────────────────────────
cmd_disk() {
  title "磁盘与存储"

  section "磁盘使用情况"
  df -hT | grep -v tmpfs | grep -v devtmpfs

  section "inode 使用情况"
  df -i | grep -v tmpfs | grep -v devtmpfs | \
    awk 'NR==1{print} NR>1{
      pct=$5; gsub(/%/,"",pct);
      if(pct+0 >= 90) printf "\033[0;31m%s\033[0m\n", $0
      else print
    }'

  section "大文件 Top 20（全盘，>100MB）"
  find / -xdev -type f -size +100M 2>/dev/null | \
    xargs ls -lh 2>/dev/null | sort -k5 -rh | head -20 | \
    awk '{printf "%-10s %s\n", $5, $9}'

  section "大目录 Top 10（/var, /home, /opt）"
  du -sh /var /home /opt /tmp /usr 2>/dev/null | sort -rh | head -10

  section "挂载点与磁盘类型"
  lsblk -f 2>/dev/null || fdisk -l 2>/dev/null | grep "Disk /"

  section "磁盘健康（smartctl）"
  if command -v smartctl &>/dev/null; then
    lsblk -d -o NAME 2>/dev/null | tail -n +2 | while read disk; do
      echo "── /dev/${disk}:"
      smartctl -H "/dev/${disk}" 2>/dev/null | grep "SMART overall" || echo "  N/A（虚拟磁盘或权限不足）"
    done
  else
    warn "smartctl 未安装（GCP 实例使用虚拟磁盘，通常无需）"
  fi
}

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
    warn "跳过自动更新。如需执行：AUTO_UPDATE=true bash sysops.sh updates"
  fi
}

# ─── 10. 备份 ────────────────────────────────────────────────────────────────
cmd_backup() {
  title "备份关键配置"
  require_root
  init_dirs

  local backup_file="${BACKUP_DIR}/configs_${TIMESTAMP}.tar.gz"
  section "备份系统配置文件"

  local backup_paths=(
    "/etc/ssh/sshd_config"
    "/etc/ufw"
    "/etc/fail2ban"
    "/etc/nginx"
    "/etc/apache2"
    "/etc/mysql"
    "/etc/crontab"
    "/var/spool/cron/crontabs"
    "/etc/systemd/system"
    "/etc/hosts"
    "/etc/fstab"
    "/etc/resolv.conf"
    "/etc/sudoers"
    "/etc/sudoers.d"
  )

  # 过滤存在的路径
  local existing=()
  for p in "${backup_paths[@]}"; do
    [[ -e "$p" ]] && existing+=("$p")
  done

  if [[ ${#existing[@]} -eq 0 ]]; then
    error "没有找到可备份的配置文件"
    return 1
  fi

  tar -czf "$backup_file" "${existing[@]}" 2>/dev/null
  local size
  size=$(ls -lh "$backup_file" | awk '{print $5}')
  log "备份完成: ${backup_file} (${size})"

  section "备份文件列表"
  ls -lh "${BACKUP_DIR}/" | tail -10

  section "清理旧备份（保留最近 7 个）"
  ls -t "${BACKUP_DIR}"/configs_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null && \
    log "旧备份清理完成" || true
}

# ─── 11. 性能调优 ────────────────────────────────────────────────────────────
cmd_tune() {
  title "性能状态与调优建议"

  section "当前 sysctl 关键参数"
  local params=(
    "vm.swappiness"
    "net.core.somaxconn"
    "net.ipv4.tcp_max_syn_backlog"
    "net.ipv4.tcp_fin_timeout"
    "net.ipv4.tcp_tw_reuse"
    "net.core.rmem_max"
    "net.core.wmem_max"
    "fs.file-max"
  )
  for p in "${params[@]}"; do
    printf "%-40s = %s\n" "$p" "$(sysctl -n "$p" 2>/dev/null || echo 'N/A')"
  done

  section "文件描述符"
  echo "系统上限: $(sysctl -n fs.file-max 2>/dev/null)"
  echo "当前使用: $(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1}')"

  section "透明大页（THP）"
  local thp
  thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo 'N/A')
  echo "THP 状态: $thp"
  echo "$thp" | grep -q '\[always\]' && warn "建议数据库场景关闭 THP：echo never > /sys/kernel/mm/transparent_hugepage/enabled"

  section "调优建议"
  local mem_gb
  mem_gb=$(free -g | awk 'NR==2{print $2}')

  local swappiness
  swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo 60)
  [[ $swappiness -gt 10 ]] && warn "vm.swappiness=${swappiness}，建议 Web 服务器设为 10：sysctl -w vm.swappiness=10"

  local somaxconn
  somaxconn=$(sysctl -n net.core.somaxconn 2>/dev/null || echo 128)
  [[ $somaxconn -lt 1024 ]] && warn "net.core.somaxconn=${somaxconn}，高并发场景建议 ≥ 1024"

  echo ""
  cat <<'EOF'
  推荐 /etc/sysctl.d/99-gcp-optimize.conf 配置：
  ──────────────────────────────────────────────
  vm.swappiness = 10
  net.core.somaxconn = 65535
  net.ipv4.tcp_max_syn_backlog = 65535
  net.ipv4.tcp_fin_timeout = 15
  net.ipv4.tcp_tw_reuse = 1
  net.core.rmem_max = 16777216
  net.core.wmem_max = 16777216
  fs.file-max = 2097152
  ──────────────────────────────────────────────
  应用：sysctl --system
EOF
}

# ─── 12. 全量报告 ────────────────────────────────────────────────────────────
cmd_full_report() {
  init_dirs
  title "生成全量运维报告 → ${REPORT_FILE}"
  echo "报告生成时间: $(date)" | tee "$REPORT_FILE"
  echo "脚本版本: v${SCRIPT_VERSION}" | tee -a "$REPORT_FILE"
  echo "" | tee -a "$REPORT_FILE"

  for cmd in overview resources processes services logs security network disk; do
    { "cmd_${cmd}"; } 2>&1 | tee -a "$REPORT_FILE"
  done

  echo ""
  log "✅ 全量报告已保存至: ${REPORT_FILE}"
  echo "   大小: $(ls -lh "$REPORT_FILE" | awk '{print $5}')"
}

# ─── 使用说明 ─────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}${CYAN}sysops.sh v${SCRIPT_VERSION}${RESET} — GCP Ubuntu VPS 运维脚本"
  echo ""
  echo -e "${BOLD}用法:${RESET}"
  echo "  sudo bash sysops.sh <命令>"
  echo ""
  echo -e "${BOLD}命令:${RESET}"
  printf "  %-18s %s\n" "overview"    "系统概览（主机、GCP 元数据、IP）"
  printf "  %-18s %s\n" "resources"   "CPU / 内存 / 磁盘 / 网络资源监控"
  printf "  %-18s %s\n" "processes"   "进程管理（Top CPU/内存、僵尸进程）"
  printf "  %-18s %s\n" "services"    "服务状态 & 监听端口"
  printf "  %-18s %s\n" "logs"        "日志分析（错误、认证失败、OOM）"
  printf "  %-18s %s\n" "security"    "安全审计（防火墙、SSH 暴破、SUID）"
  printf "  %-18s %s\n" "network"     "网络诊断（路由、DNS、GCP 连通性）"
  printf "  %-18s %s\n" "disk"        "磁盘与存储（使用率、大文件、健康）"
  printf "  %-18s %s\n" "updates"     "系统更新检查 & 安全补丁（需 root）"
  printf "  %-18s %s\n" "backup"      "备份关键配置文件（需 root）"
  printf "  %-18s %s\n" "tune"        "性能参数检查 & 调优建议"
  printf "  %-18s %s\n" "report"      "全量报告（所有模块，输出到文件）"
  printf "  %-18s %s\n" "all"         "交互式依次运行所有模块"
  echo ""
  echo -e "${BOLD}示例:${RESET}"
  echo "  sudo bash sysops.sh overview"
  echo "  sudo bash sysops.sh resources"
  echo "  sudo bash sysops.sh report"
  echo "  AUTO_UPDATE=true sudo bash sysops.sh updates"
  echo ""
}

# ─── 交互式全模块 ─────────────────────────────────────────────────────────────
cmd_all() {
  for cmd in overview resources processes services logs security network disk tune; do
    "cmd_${cmd}"
    echo -e "\n${YELLOW}按 Enter 继续，Ctrl+C 退出...${RESET}"
    read -r
  done
}

# ─── 入口 ─────────────────────────────────────────────────────────────────────
main() {
  case "${1:-help}" in
    overview)   cmd_overview   ;;
    resources)  cmd_resources  ;;
    processes)  cmd_processes  ;;
    services)   cmd_services   ;;
    logs)       cmd_logs       ;;
    security)   cmd_security   ;;
    network)    cmd_network    ;;
    disk)       cmd_disk       ;;
    updates)    cmd_updates    ;;
    backup)     cmd_backup     ;;
    tune)       cmd_tune       ;;
    report)     cmd_full_report ;;
    all)        cmd_all        ;;
    -h|--help|help) usage      ;;
    *)
      error "未知命令: ${1}"
      usage
      exit 1
      ;;
  esac
}

main "$@"