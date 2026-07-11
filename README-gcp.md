# vps_sysops — GCP Ubuntu VPS 全面运维脚本

一套面向 Google Cloud Platform Ubuntu VPS 的生产级 Shell 运维脚本，涵盖 **12 个功能模块**：
系统信息、资源监控、进程管理、服务管理、日志分析、安全审计、网络诊断、磁盘存储、
系统更新、配置备份、性能调优、全量报告。脚本自动适配 GCP 元数据 API，也可在非 GCP 环境优雅降级。

---

## Table of Contents

- [Project Description](#project-description)
- [Features / Functional Modules](#features--functional-modules)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Scheduling / Automation](#scheduling--automation)
- [Repository Layout](#repository-layout)

---

## Project Description

`vps_sysops` 是一个单文件 Bash 脚本工具集，专为 GCP (Google Cloud Platform) 上的
Ubuntu VPS 实例设计。它整合了系统运维中最常用的 12 类操作 — 从基础的主机信息检查到
安全审计、从日志分析到性能调优 — 统一到一个 `sysops.sh` 命令接口下。

脚本通过 GCP 元数据服务（`metadata.google.internal`）自动读取实例 ID、机型、可用区、
内外网 IP 等云环境信息；当检测到不在 GCE 实例上时，自动降级为通用 Linux 运维模式。

**目标机型：** e2-micro / e2-standard 系列，Ubuntu 24.04/25.10 LTS
**脚本版本：** v2.0.0

---

## Features / Functional Modules

### 1. 系统概览 (`overview`)
主机名、操作系统版本、内核、架构、运行时长，以及 GCP 元数据
（实例 ID、机器类型、可用区、内外网 IP、项目 ID）。

```bash
bash sysops.sh overview
```

若非 GCP 环境，自动通过 `ifconfig.me` 获取外部 IP。

### 2. 资源监控 (`resources`)
CPU 使用率与负载、内存与 Swap 使用率（含 >85% 告警）、磁盘空间
（≥90% 红色高亮、≥75% 黄色警告）、磁盘 I/O（iostat）、网络接口与 TCP 连接统计。

```bash
bash sysops.sh resources
```

### 3. 进程管理 (`processes`)
Top 10 CPU 占用进程、Top 10 内存占用进程、僵尸进程检测与列表、
系统进程总数统计。

```bash
bash sysops.sh processes
```

### 4. 服务管理 (`services`)
关键服务状态检查（ssh、ufw、fail2ban、nginx、apache2、mysql、postgresql、
docker、chronyd、ntp 等），含开机启动状态。最近 24h 启动/停止事件、
以及 `ss -tlnp` 监听端口一览。

```bash
bash sysops.sh services
```

### 5. 日志分析 (`logs`)
系统错误日志（syslog 最近 24h）、认证失败 / SSH 暴力破解尝试、
内核 OOM (Out-of-Memory) 事件、磁盘 I/O 错误、`/var/log` 大文件 Top 10。

```bash
bash sysops.sh logs
```

### 6. 安全审计 (`security`)
UFW 防火墙状态与规则、iptables 规则统计、SSH 暴力破解 IP Top 10、
fail2ban 当前被封 IP、异常 SUID/SGID 文件排查、近期新增用户、
sudo 权限用户列表、SSH 密钥认证文件检查。

```bash
sudo bash sysops.sh security
```

### 7. 网络诊断 (`network`)
网络接口详情、路由表、DNS 解析测试、GCP 端点连通性
（metadata、storage、compute API）、活跃远程 IP Top 5、
各网卡 RX/TX 流量统计。

```bash
bash sysops.sh network
```

### 8. 磁盘与存储 (`disk`)
磁盘使用率（含 ≥90% 红色告警）、inode 使用率、全盘大文件 Top 20（>100MB）、
大目录 Top 10（/var、/home、/opt 等）、挂载点与文件系统类型、
SMART 磁盘健康检查。

```bash
bash sysops.sh disk
```

### 9. 系统更新 (`updates`)
可用更新包数量、安全补丁列表、已安装包统计、最近安装/升级历史。
设置 `AUTO_UPDATE=true` 可自动执行安全更新。

```bash
sudo bash sysops.sh updates
AUTO_UPDATE=true sudo bash sysops.sh updates
```

### 10. 备份 (`backup`)
将关键系统配置文件（sshd、ufw、fail2ban、nginx、mysql、crontab、
systemd units、hosts、fstab、sudoers 等）打包为 tar.gz 存档，
自动清理旧备份（保留最近 7 个）。

```bash
sudo bash sysops.sh backup
```

备份路径：`/var/backups/sysops/configs_<timestamp>.tar.gz`

### 11. 性能调优 (`tune`)
检查当前 sysctl 关键参数（swappiness、somaxconn、tcp_fin_timeout、
tcp_tw_reuse、rmem_max、wmem_max、file-max 等）、文件描述符使用、
透明大页 (THP) 状态，并给出高并发 / 数据库场景的调优建议与
`/etc/sysctl.d/99-gcp-optimize.conf` 推荐配置。

```bash
bash sysops.sh tune
```

### 12. 全量报告 (`report`)
依次执行 overview → resources → processes → services → logs → security →
network → disk 共 8 个模块，输出保存到 `/tmp/sysops_reports/` 时间戳文件中。
适合定时巡检和故障排查归档。

```bash
sudo bash sysops.sh report
```

### 附加：交互式全模块 (`all`)
逐模块交互式运行（overview → resources → … → tune），按 Enter 继续。

```bash
sudo bash sysops.sh all
```

---

## Prerequisites

| 组件 | 最低版本 | 说明 |
|------|---------|------|
| `bash` | 4.0+ | 使用 `set -euo pipefail` |
| `coreutils` | — | 标准 Linux 工具集 |
| `curl` | — | GCP 元数据请求 |
| `lsb-release` | — | OS 版本检测 |

### 可选依赖（脚本会自动检测并优雅跳过）

| 工具 | 用途 | 安装命令 |
|------|------|---------|
| `iostat` | 磁盘 I/O 监控 | `apt install sysstat` |
| `smartctl` | SMART 磁盘健康 | `apt install smartmontools` |
| `ss` | TCP 连接统计 | 通常预装（`iproute2`） |
| `dig` | DNS 解析诊断 | `apt install dnsutils` |
| `fail2ban-client` | 被封 IP 查询 | `apt install fail2ban` |
| `ufw` | 防火墙审计 | `apt install ufw` |
| `bc` | 浮点运算 | `apt install bc` |

### 权限说明

- **无需 root：** overview、resources、processes、services、logs、network、disk、tune
- **需要 root：** security（部分子项）、updates、backup、report（含 security）

---

## Quick Start

### 1. 获取脚本

```bash
# 克隆仓库
git clone <repo-url> vps_sysops
cd vps_sysops

# 或直接 scp 到服务器
scp sysops.sh user@your-gcp-ip:~/
```

### 2. 添加执行权限

```bash
chmod +x sysops.sh
```

### 3. 查看系统概览（无需 root）

```bash
bash sysops.sh overview
```

输出示例：

```
══════════════════════════════════════
  系统概览
══════════════════════════════════════

▶ 主机信息
────────────────────────────────────────
主机名:       gcp-vps2
操作系统:     Ubuntu 25.10
内核版本:     6.17.0-1018-gcp
系统架构:     x86_64
当前时间:     2026-06-28 16:42:00 UTC
运行时长:     up 15 days, 3 hours

▶ GCP 元数据
────────────────────────────────────────
实例 ID:      8425274972061862870
机器类型:     e2-standard-2
可用区:       us-central1-c
外部 IP:      34.172.33.185
内部 IP:      10.128.0.4
项目 ID:      40129528744
```

### 4. 安全审计（需要 root）

```bash
sudo bash sysops.sh security
```

### 5. 生成完整报告

```bash
sudo bash sysops.sh report
# 报告文件：/tmp/sysops_reports/report_20260628_164200.txt
```

### 6. 交互式逐模块运行

```bash
sudo bash sysops.sh all
```

### 7. 各模块独立运行

```bash
bash sysops.sh overview    # 系统概览
bash sysops.sh resources   # 资源监控
bash sysops.sh processes   # 进程管理
bash sysops.sh services    # 服务状态
bash sysops.sh logs        # 日志分析
sudo bash sysops.sh security  # 安全审计
bash sysops.sh network     # 网络诊断
bash sysops.sh disk        # 磁盘存储
sudo bash sysops.sh updates   # 更新检查
sudo bash sysops.sh backup    # 配置备份
bash sysops.sh tune        # 性能调优
```

---

## Configuration

### 全局变量

脚本顶部的配置常量可直接修改：

```bash
LOG_DIR="/var/log/sysops"           # 日志目录
REPORT_DIR="/tmp/sysops_reports"    # 报告输出目录
BACKUP_DIR="/var/backups/sysops"    # 备份存放目录
SCRIPT_VERSION="2.0.0"              # 脚本版本
```

### 自动更新模式

在执行 `updates` 模块时传入环境变量启用：

```bash
AUTO_UPDATE=true sudo bash sysops.sh updates
```

或在 crontab 中使用：

```cron
0 4 * * 0 AUTO_UPDATE=true /usr/local/bin/sysops.sh updates
```

### 关键服务列表

`services` 模块检查的服务列表可在脚本中自定义：

```bash
local services=("ssh" "ufw" "fail2ban" "nginx" "apache2" "mysql" "postgresql"
                "docker" "google-cloud-ops-agent" "stackdriver-agent" "chronyd" "ntp")
```

### 备份路径

`backup` 模块的备份文件列表可在脚本中自定义：

```bash
local backup_paths=(
    "/etc/ssh/sshd_config"
    "/etc/ufw"
    "/etc/fail2ban"
    "/etc/nginx"
    # ... 按此格式添加
)
```

### 性能调优参数

`tune` 模块检查的 sysctl 参数列表可在 `params` 数组中添加：

```bash
local params=(
    "vm.swappiness"
    "net.core.somaxconn"
    # ... 按此格式添加
)
```

---

## Scheduling / Automation

### Crontab 示例

```cron
# 每 30 分钟生成一次报告
*/30 * * * * /usr/local/bin/sysops.sh report

# 每天凌晨 2 点执行安全审计（输出重定向到日志）
0 2 * * * /usr/local/bin/sysops.sh security >> /var/log/sysops/security-audit.log 2>&1

# 每周日凌晨 4 点自动安装安全更新
0 4 * * 0 AUTO_UPDATE=true /usr/local/bin/sysops.sh updates >> /var/log/sysops/update.log 2>&1

# 每天凌晨 3 点备份关键配置
0 3 * * * /usr/local/bin/sysops.sh backup

# 每小时检查资源使用率（仅告警阈值触发时记录）
0 * * * * /usr/local/bin/sysops.sh resources | grep -E "WARN|ERROR" >> /var/log/sysops/alerts.log 2>&1
```

### 部署到远程 VPS

```bash
# 复制脚本到远程主机
scp sysops.sh caozuohua99@<remote-ip>:/usr/local/bin/sysops.sh

# 远程执行
ssh caozuohua99@<remote-ip> "chmod +x /usr/local/bin/sysops.sh"
ssh caozuohua99@<remote-ip> "sudo /usr/local/bin/sysops.sh report"
```

### 通过 GCP gcloud SSH 远程执行

```bash
# 上传并执行
gcloud compute scp sysops.sh instance-20260413-080555:/tmp/ \
  --zone=us-central1-c
gcloud compute ssh instance-20260413-080555 \
  --zone=us-central1-c \
  --command="sudo bash /tmp/sysops.sh report"
```

### 报告归档

定时收集报告到本地：

```bash
# 每日拉取远程报告
gcloud compute scp instance-20260413-080555:/tmp/sysops_reports/report_*.txt \
  ./reports/ --zone=us-central1-c
```

### 性能调优配置

根据 `tune` 模块建议，创建调优配置文件并应用：

```bash
sudo tee /etc/sysctl.d/99-gcp-optimize.conf << 'EOF'
vm.swappiness = 10
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
fs.file-max = 2097152
EOF

sudo sysctl --system
```

---

## Repository Layout

```
vps_sysops/
├── README.md       # 本文档
└── sysops.sh       # 主脚本文件（581 行，12 个功能模块）
```

单文件设计 — 无外部依赖，复制到任何 Ubuntu 服务器即可使用。

---

## 命令速查表

| 命令 | 功能 | 需要 root |
|------|------|:---------:|
| `overview` | 系统概览 + GCP 元数据 | 否 |
| `resources` | CPU / 内存 / 磁盘 / 网络监控 | 否 |
| `processes` | Top 进程 + 僵尸进程检测 | 否 |
| `services` | 关键服务状态 + 监听端口 | 否 |
| `logs` | 错误日志 / 认证失败 / OOM | 否 |
| `security` | 防火墙 / SSH 暴破 / SUID / sudo | 部分 |
| `network` | 路由 / DNS / GCP 连通性 / 流量 | 否 |
| `disk` | 磁盘使用 / inode / 大文件 / SMART | 否 |
| `updates` | 可用更新 & 安全补丁 | 是 |
| `backup` | 备份 ssh/nginx/mysql 等配置到 /var/backups/sysops | 是 |
| `tune` | sysctl 参数检查 + 高并发/数据库调优建议 | 否 |
| `report` | 全量报告输出到 /tmp/sysops_reports/ | 是 |
| `all` | 交互式依次运行所有模块 | 部分 |
