# vps_sysops — VPS 运维工具包（模块化）

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04%2B-orange.svg)](https://ubuntu.com)
[![Shell](https://img.shields.io/badge/shell-bash%204.4%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Security Policy](https://img.shields.io/badge/security-policy-red.svg)](SECURITY.md)

> [CHANGELOG](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [License](LICENSE)

一套面向 Ubuntu VPS 的生产级 Shell 运维工具包，按**模块化架构**组织：
`ops.sh` 是统一交互入口，各功能拆到 `scripts/` 下独立、可单独调用的脚本，
共享 `config/ops.conf` 一处配置。覆盖 **20 个功能模块** —— 从基础安全加固、
运行环境部署，到系统监控、进程/服务/日志/安全/网络/磁盘诊断、更新检查、配置备份、性能调优，
再到全量报告和 Mem0 服务级检查。

## 架构规范

```
vps_sysops/
├── ops.sh                  # 总入口菜单（交互式，统一调度 scripts/ 下模块）
├── a2a-bridge/             # 两台 Hermes 间的私有 A2A 桥接与 MCP 适配器
├── config/
│   ├── ops.conf            # 通用默认配置与主机 profile 自动选择
│   └── hosts/              # GCP / Azure / AWS 非敏感主机配置
├── docs/
│   └── current-state.md    # 已验证的公网、Tailscale、端口与服务拓扑
├── scripts/                # 各功能模块（独立可运行，统一 source ../config/ops.conf）
│   ├── 01_harden.sh         # 基础安全加固（防火墙/fail2ban/自动更新/swap）
│   ├── 02_setup_env.sh      # 部署运行环境（Docker/Python/Node.js）
│   ├── 03_monitor.sh        # 健康检查（cron 用，飞书告警）
│   ├── 04_backup.sh         # 备份 + 日志轮转（cron 用）
│   ├── 05_overview.sh       # 系统概览（主机 + 云元数据自动识别 GCP/Azure）
│   ├── 06_processes.sh      # 进程管理（Top CPU/内存、僵尸进程）
│   ├── 07_resources.sh      # 资源监控（CPU/内存/磁盘/网络）
│   ├── 08_services.sh       # 服务管理（关键服务状态 + 监听端口）
│   ├── 09_logs.sh           # 日志分析（错误/认证失败/OOM/磁盘错误）
│   ├── 10_security_audit.sh # 安全审计（防火墙/SSH 暴破/SUID/sudo/密钥）
│   ├── 11_network.sh        # 网络诊断（路由/DNS/GCP 连通性/流量）
│   ├── 12_disk.sh           # 磁盘与存储（使用率/inode/大文件/SMART）
│   ├── 13_updates.sh        # 系统更新检查 & 安全补丁
│   ├── 14_web_stack.sh      # x-ui/Nginx/Let’s Encrypt（GCP Ubuntu）
│   ├── 15_tune.sh           # 性能调优建议
│   ├── 16_report.sh         # 全量报告（汇聚全部模块，输出到 REPORT_DIR）
│   ├── mem0.sh              # Mem0 服务状态/健康/日志/显式 smoke
│   ├── agent_ctl.sh         # GCP Hermes Agent 服务管理（委托 agent-ctl）
│   └── mem0_backup.sh       # Mem0 PostgreSQL 低资源备份/校验/恢复 smoke
├── system/                 # 通用及 GCP 专属的可复现系统配置、Tailscale ACL
│   └── bin/ops              # 注册到 /usr/local/bin/ops 的全局入口
├── tests/                  # Shell/profile/Python 与 SQLite 备份 smoke tests
└── README.md               # 本文档
```

**约定**

- 每个 `scripts/*.sh` 顶部 `source "${SCRIPT_DIR}/../config/ops.conf"`，配置集中管理。
- 脚本以 `cmd_<模块名>` 定义主逻辑，末尾 `cmd_<模块名>` 直接调用（可被 `ops.sh` 与其他脚本 source/调用）。
- 颜色与日志函数（`log`/`warn`/`error`/`title`/`section`）每个脚本自带，互不依赖。
- 幂等设计：可重复运行，已安装组件自动跳过。

## 功能模块速查表

| 菜单项 | 脚本 | 功能 | 需要 root |
|------|------|------|:---------:|
| 1 | `01_harden.sh` | 基础安全加固 | 是 |
| 2 | `02_setup_env.sh` | 部署运行环境 | 是 |
| 3 | `03_monitor.sh` | 系统监控/健康检查（cron） | 否 |
| 4 | `04_backup.sh` | 一致性备份 + 日志轮转（cron） | 是 |
| 5 | `05_overview.sh` | 系统概览 + GCP 元数据 | 否 |
| 6 | `07_resources.sh` | CPU/内存/磁盘/网络监控 | 否 |
| 7 | `06_processes.sh` | Top 进程 + 僵尸进程检测 | 否 |
| 8 | `08_services.sh` | 关键服务状态 + 监听端口 | 否 |
| 9 | `09_logs.sh` | 错误日志/认证失败/OOM | 否 |
| 10 | `10_security_audit.sh` | 防火墙/SSH 暴破/SUID/sudo | 部分 |
| 11 | `11_network.sh` | 路由/DNS/GCP 连通性/流量 | 否 |
| 12 | `12_disk.sh` | 磁盘使用/inode/大文件/SMART | 否 |
| 13 | `13_updates.sh` | 可用更新 & 安全补丁 | 是 |
| 14 | `15_tune.sh` | sysctl 参数检查 + 调优建议 | 否 |
| 15 | `16_report.sh` | 全量报告输出到 `REPORT_DIR` | 部分 |
| 16 | — | 交互式依次运行所有模块 | 部分 |
| 17 | `14_web_stack.sh` | x-ui/Nginx/Let’s Encrypt Web 栈 | 是 |
| 18 | `mem0.sh` | Mem0 API/Dashboard/Compose 服务级检查 | 否（本机 logs 需 Docker 权限） |
| — | `mem0_backup.sh` | Mem0 PostgreSQL dump、校验和、临时库恢复 smoke | 是（AWS profile） |
| 19 | `agent_ctl.sh` | GCP Hermes Agent 服务管理 | 否（启停由 agent-ctl 内部 sudo） |

> 说明：模块编号沿用历史序号（06 在 07 前、13 后是 15、报告为 16），菜单已按 `scripts/` 实际文件名映射，新增脚本请勿重排既有编号。

## 使用步骤

1. 上传到服务器并解压：

   ```bash
   scp -r vps_sysops user@your-vps-ip:~/
   ssh user@your-vps-ip
   cd vps_sysops
   chmod +x ops.sh scripts/*.sh
   ```

2. 已知主机会按 hostname 自动选择 `config/hosts/gcp.conf`、
   `config/hosts/azure.conf` 或 `config/hosts/aws.conf`。其他主机编辑
   `config/ops.conf`，或用 `VPS_PROFILE=gcp|azure|aws` 显式选择配置。

3. 运行菜单（交互式）：

   ```bash
   ./ops.sh            # 启动交互式菜单
   ./ops.sh --help     # 显示模块列表与用法
   ```

   或直接执行单个脚本：

   ```bash
   sudo bash scripts/01_harden.sh
   bash scripts/07_resources.sh
   bash scripts/05_overview.sh --help    # 每个脚本都支持 -h/--help
   bash scripts/mem0.sh status --format json
   ```

   三台 VPS 已注册全局入口，SSH 登录后可直接运行：

   ```bash
   ops              # 交互式菜单
   ops --help       # 查看入口帮助
   ```

   > **统一约定**：`ops.sh` 与所有 `scripts/*.sh` 均支持 `-h` / `--help` 打印用法后立即退出；
   > 单独运行脚本时无需任何参数即可直接执行对应模块。

## 云环境识别（GCP / Azure 自动适配）

`scripts/05_overview.sh` 的「云环境元数据」段落会自动探测云厂商，**无需手动切换**：

- **GCP**：探测 `metadata.google.internal`，读取实例 ID、机型、可用区、内外网 IP、项目 ID。
- **Azure**：探测 IMDS `169.254.169.254/metadata/instance`，读取 VM 名称、大小、位置、资源组、订阅 ID、内外网 IP。
- **其他环境**（裸机 / 非云 VPS）：两项探测均失败，降级为 `ifconfig.me` 取外网 IP + `hostname -I` 取内网 IP。

添加 `--help` 后，所有脚本与入口都具备自说明能力：

```bash
./ops.sh --help                              # 模块列表 + 用法
bash scripts/05_overview.sh --help           # 单脚本用法
bash scripts/07_resources.sh                 # 直接执行（无需参数）
```

当前两台 VPS 的静态公网 IP、Tailscale IP、ACL 端口矩阵、newAPI/x-ui/Xray
链路和备份策略见 [`docs/current-state.md`](docs/current-state.md)。该文件是运维事实
清单；网络或服务配置改变后应同步更新。

## 监控服务（Hermes Agent）

`config/ops.conf` 中的 `MONITOR_SERVICES` 指定需要健康检查的服务。通用默认仅监控
Hermes Agent 网关；GCP/Azure profile 会覆盖为各自主机的完整关键服务列表：

```conf
MONITOR_SERVICES="hermes-gateway.service"
```

- GCP：SSH、Tailscale、Docker、nginx、x-ui、newAPI、A2A、iptables hardening、Certbot timer。
- Azure：SSH、Tailscale，以及用户 `caozuohua` 的 Hermes gateway 与 A2A。

`03_monitor.sh` 与 `08_services.sh` 会先查系统级 unit，再按 `MONITOR_USER` 查用户级
unit，适配两台机器不同的 A2A 部署方式。

Hermes 网关通过 `hermes gateway install` 注册为 **用户级 systemd 服务**
（`~/.config/systemd/user/hermes-gateway.service`），`03_monitor.sh` 会按
**系统级 → 用户级**两级自动检测，无论注册在哪一层都能正确判断存活，不会误报。

```bash
# 查看 Hermes 网关状态
hermes gateway status
# 安装为后台服务（首次）
hermes gateway install
```

## 暴力破解防护（Fail2Ban 联动 UFW）

`10_security_audit.sh` 与 `03_monitor.sh` 可检测 SSH 暴破，真正拦截依赖 **Fail2Ban → 防火墙** 联动。

### 已知环境限制（根因）

本机 fail2ban v1.0.2 的 **action 执行机制整体失效**：ban 事件能产生（内存���禁 + 日志 `Ban <IP>`），
但 `actionban` 命令**从不执行**（已排除 systemd CapabilityBoundingSet / AppArmor / PATH / nftables 模板问题，
并用 action 调试日志确认进程从不调用 nft/ufw）。因此 fail2ban 原生无法把封禁下发到防火墙。

### 解决方案：Fail2Ban → UFW 同步守护

- `scripts/sync_fail2ban_to_ufw.sh`：读取 fail2ban **当前实际封禁列表**，自动 `ufw deny`，
  并在 fail2ban 解封后清理对应 UFW 规则（**双向同步，跟随 fail2ban 生命周期，不无限膨胀**）。
- **白名单**内置：回环 / 私有网段（10./172.16-31./192.168./169.254.）/ 本机公网 IP / 管理员 IP / UFW 已 allow 的 IP
  永不封禁，防止误锁自己。
- 触发：`/etc/systemd/system/failsync.{service,timer}` 每 30 秒跑一次（近实时，消除 cron 空窗）。
  早期曾用 `systemd path` 单元监听 `fail2ban.log`，但因 fail2ban 长期持有日志 fd 不触发 `PathChanged`，改为 timer。

```bash
# 手动触发一次同步
sudo bash scripts/sync_fail2ban_to_ufw.sh
# 查看 timer 状态
systemctl status failsync.timer
```

> 当前已封禁的暴破 IP 见 `sudo ufw status`（标记 `bruteforce-` 为手动补封、`f2b-auto` 为同步脚本自动维护）。

## 系统层配置（纳入版本管理）

部分加固配置位于 `/etc` 与 systemd 下，**不在 `scripts/` 内**。为可复现部署，已全部复制到
项目 `system/` 目录（保持原绝对路径结构），与代码一同版本化：

```
system/
├── etc/
│   ├── fail2ban/
│   │   ├── jail.local              # fail2ban 加强配置（maxretry/bantime/recidive）
│   │   └── action.d/
│   │       └── ufw-simple.conf     # 极简 UFW action（绕开失效的 nftables action）
│   ├── ssh/
│   │   └── sshd_config.d/
│   │       └── 99-bruteforce.conf  # sshd MaxAuthTries=3
│   └── systemd/
│       └── system/
│           ├── failsync.service    # 触发 sync_fail2ban_to_ufw.sh
│           └── failsync.timer      # 每 30s 触发
├── gcp/etc/                        # GCP 当前线上配置的脱敏副本
│   ├── apt/sources.list.d/         # Ubuntu 26.04 的 Docker/Tailscale 等源
│   ├── ssh/sshd_config.d/          # 禁止 Agent/远程转发与 tunnel
│   ├── sysctl.d/                   # fq + BBR + swappiness
│   └── systemd/system/             # newAPI、iptables、A2A Tailscale wait
└── tailscale/grants.hujson         # 已验证的 tailnet 最小权限策略
```

`system/gcp/` 中不包含 `/root/new-api/.env`、x-ui 秘密路径、TLS 私钥或 A2A Token。
APT source 文件引用的厂商 keyring 仍须先通过各厂商官方安装流程创建。

### 部署到新机器 / 重装后恢复

```bash
# 1. fail2ban 配置
sudo cp system/etc/fail2ban/jail.local /etc/fail2ban/jail.local
sudo cp system/etc/fail2ban/action.d/ufw-simple.conf /etc/fail2ban/action.d/ufw-simple.conf
sudo fail2ban-client reload

# 2. sshd 加固（仅降 MaxAuthTries，不改端口/密码）
sudo cp system/etc/ssh/sshd_config.d/99-bruteforce.conf /etc/ssh/sshd_config.d/
sudo sshd -t && sudo systemctl restart ssh

# 3. UFW 同步守护（推荐使用 01_harden.sh 自动安装）
sudo cp system/etc/systemd/system/failsync.service /etc/systemd/system/
sudo cp system/etc/systemd/system/failsync.timer  /etc/systemd/system/
# 手工部署时，将 @PROJECT_ROOT@ 替换为项目绝对路径
sudo sed -i "s#@PROJECT_ROOT@#/实际/项目/路径#g" /etc/systemd/system/failsync.service
sudo systemctl daemon-reload
sudo systemctl enable --now failsync.timer
```

> `01_harden.sh` 会把同步脚本安装到 `/usr/local/libexec/`，因此正常安装流程不需要修改路径。

## x-ui / Nginx / Let’s Encrypt（GCP Ubuntu）

`scripts/14_web_stack.sh` 不负责安装来源不明的 x-ui 二进制；它假设 x-ui 已安装并监听本机端口，负责 Nginx 反代、HTTPS 证书和面板路径加固。

非敏感的 GCP 域名与端口已在 `config/hosts/gcp.conf`；秘密路径和邮箱写入被
`.gitignore` 排除的 `config/hosts/gcp.local.conf`：

```conf
XUI_WEB_BASE_PATH="/xui_a1b2c3d4e5f6g7h8"
LETSENCRYPT_EMAIL="admin@example.com"
```

然后执行：

```bash
sudo bash scripts/14_web_stack.sh --install
sudo bash scripts/14_web_stack.sh --xui-path /xui_a1b2c3d4e5f6g7h8
sudo bash scripts/14_web_stack.sh --issue
sudo bash scripts/14_web_stack.sh --status
sudo bash scripts/14_web_stack.sh --renew --dry-run
```

模块会将 x-ui 只代理到 `127.0.0.1:${XUI_PANEL_PORT}`，根路径返回 404，面板路径通过 Nginx HTTPS 访问，并在修改 x-ui SQLite 数据库前自动生成备份。WebSocket 所需的 Upgrade/Connection 头也会转发。

证书续期由 Certbot 自带定时机制负责；脚本的 `--renew` 用于手工验证或补充执行，续期成功后 reload Nginx。

### GCP 必须额外配置

Ubuntu 内的 UFW 放行不等于 GCP VPC 防火墙放行。请在 GCP 防火墙规则中仅对需要的来源开放 TCP 80/443；x-ui 面板端口（例如 2053）不应开放到公网。域名 DNS 的 A/AAAA 记录必须指向 VPS，Let’s Encrypt HTTP-01 验证需要公网 TCP 80 可达。

### 安全边界

- `XUI_WEB_BASE_PATH` 不是 x-ui 的 `secret` 字段；模块修改的是 `settings.webBasePath`。
- 随机路径只是降低扫描噪声，不是认证机制；x-ui 自身密码仍必须使用强密码。
- 脚本不会自动修改 GCP 防火墙、x-ui 管理员密码或第三方 DNS。
- 申请证书前先确认域名已解析、80/443 未被其他服务占用，并先在快照或测试机验证。

## 私有 Hermes A2A

`a2a-bridge/` 来自 Azure 当前运行分支，包含桥接服务、MCP 适配器、systemd unit
模板和安全策略。服务只绑定各自的 Tailscale 地址，正确健康端点为 `/healthz`；
根路径和 `/health` 返回 404 是预期行为。部署配置中远程 toolsets 被禁用，详细边界见
`a2a-bridge/A2A_POLICY.md`。

运行时 `state/`、`.env`、数据库、WAL、事件日志和 Python 缓存均由 `.gitignore`
排除，禁止提交。

## 一致性本机备份

`04_backup.sh` 除普通目录归档外，还会对 profile 中的 `SQLITE_DATABASES` 使用
SQLite 在线 `.backup` API，并对副本执行 `PRAGMA integrity_check`。归档及 SHA-256
文件权限为 `0600`，默认保留 7 天。

GCP profile 覆盖 newAPI、x-ui、A2A 数据库及 newAPI `.env`；Azure profile 覆盖
A2A 数据库。备份只保存在 VPS 本机，不产生云快照费用，也不能替代异地灾备。

```bash
# 只读语法、profile 与 A2A Python 检查
bash tests/smoke.sh

# 在有 sqlite3 的 Linux root 环境测试临时 SQLite 备份、校验和与权限
sudo bash tests/backup_smoke.sh
```

## 定时任务建议

生产主机使用 systemd timer 限制资源；下面的 cron 仅作为手工部署到其他主机时的参考：

```bash
 sudo crontab -e
```

```cron
# 每 5 分钟健康检查（参考；正式三台 VPS 使用 vps-ops-monitor-*.timer）
*/5 * * * * VPS_PROFILE=gcp /home/youruser/vps_sysops/scripts/03_monitor.sh >> /var/log/vps-ops-monitor.log 2>&1

# 每天凌晨 3 点备份关键配置
0 3 * * * VPS_PROFILE=gcp /home/youruser/vps_sysops/scripts/04_backup.sh >> /var/log/vps-ops-backup.log 2>&1

# 每小时生成全量报告（归档到 REPORT_DIR）
0 * * * * /home/youruser/vps_sysops/scripts/16_report.sh >> /var/log/vps-ops-report.log 2>&1

# 每周日凌晨 4 点自动安装安全更新
0 4 * * 0 AUTO_UPDATE=true /home/youruser/vps_sysops/scripts/13_updates.sh >> /var/log/vps-ops-update.log 2>&1
```

## 配置项说明（config/ops.conf）

| 变量 | 说明 | 默认 |
|------|------|------|
| `SSH_PORT` | SSH 端口（改非默认前先确认连通） | `22` |
| `VPS_PROFILE` | 主机配置；可用 `gcp` / `azure` / `aws`，空值时按 hostname 识别 | `""` |
| `VPS_PROFILE_FILE` | 可选的外部 profile 绝对路径，优先于内置 profile | `""` |
| `EXTRA_ALLOW_PORTS` | 防火墙额外放行端口，逗号分隔 | `""` |
| `MONITOR_SERVICES` | 健康检查的服务名（空格分隔） | `hermes-gateway.service` |
| `MONITOR_USER` | 用户级 systemd unit 的所属用户 | `""` |
| `CPU_THRESHOLD` / `MEM_THRESHOLD` / `DISK_THRESHOLD` | 告警阈值（%） | `90` / `85` / `85` |
| `BACKUP_SOURCES` | 备份源目录（空格分隔） | `/etc /home` |
| `BACKUP_DEST` | 备份存放目录 | `/opt/backups` |
| `BACKUP_RETAIN_DAYS` | 备份保留天数 | `7` |
| `SQLITE_DATABASES` | 需要一致性在线备份的 SQLite 数据库 | `""` |
| `CONFIGURE_LOGROTATE` | 备份脚本是否安装日志轮转配置 | `true` |
| `TAILSCALE_ALLOW_TARGETS` / `TAILSCALE_DENY_TARGETS` | `11_network.sh` 的 ACL 探测矩阵 | `""` |
| `REPORT_DIR` | 全量报告输出目录 | `/tmp/vps-ops-reports` |
| `FEISHU_WEBHOOK` | 飞书机器人 Webhook（留空仅本地输出） | `""` |
| `MEM0_API_BASE_URL` / `MEM0_DASHBOARD_URL` | Mem0 API 与 Dashboard 地址 | AWS Tailscale 地址 |
| `MEM0_EXPECT_LOCAL_COMPOSE` | 当前 profile 是否必须存在本机 Mem0 Compose | `false` |
| `MEM0_AUTH_FILE` | Mem0 smoke 使用的主机本地认证文件 | `""` |
| `MEM0_MONITOR_ENABLED` | `03_monitor.sh` 是否检查 Mem0 API/Dashboard | `true` |
| `MEM0_SMOKE_USER_ID` / `MEM0_SMOKE_AGENT_ID` | smoke 临时记录的隔离身份 | `sysops-smoke` / `vps-sysops-smoke` |
| `MEM0_BACKUP_ENABLED` | 是否启用 Mem0 PostgreSQL 备份 | `false`（AWS 为 `true`） |
| `MEM0_BACKUP_DEST` | Mem0 dump 本机目录 | `/var/backups/vps-sysops/mem0` |
| `MEM0_BACKUP_RETAIN_DAYS` | Mem0 dump 保留天数 | `7` |
| `MEM0_BACKUP_TIMEOUT` / `MEM0_BACKUP_DISK_LIMIT` | 单次超时秒数 / 磁盘使用率上限 | `900` / `90` |

## 权限与依赖

- **无需 root**：`03_monitor` / `05_overview` / `06_processes` / `07_resources` / `08_services` /
  `09_logs` / `11_network` / `12_disk` / `15_tune`
- **需要 root**：`01_harden` / `02_setup_env` / `04_backup` / `10_security_audit`（部分子项）/
  `13_updates` / `16_report`（security、updates 子项）

可选工具（`iostat`/`smartctl`/`dig`/`fail2ban-client`/`ufw`/`bc`）脚本会自动检测并优雅跳过。

## Mem0 服务级运维

`scripts/mem0.sh` 只管理 Mem0 服务，不负责用户画像、任务或对话记忆的业务写入。
`status`、`health` 和 `logs` 可被 `luck-agent` 的固定 allowlist 调用；`smoke` 是
显式的临时写入/检索/删除验证，失败退出时会通过 `EXIT` trap 尽力清理记录。

```bash
bash scripts/mem0.sh status
bash scripts/mem0.sh health --format json
bash scripts/mem0.sh logs --tail 50
bash scripts/mem0.sh smoke --format json
```

AWS profile 的 smoke 认证文件默认为 `/etc/vps-sysops/mem0.env`，应由管理员在主机上
创建并设置为 `0600`，不得提交到仓库。普通状态和健康检查不需要认证文件。

Mem0 PostgreSQL 备份仅在 AWS 启用：`vps-ops-backup-aws.timer` 每天凌晨运行一次，
使用 `custom` 格式、`pg_dump` 流式输出、`CPUQuota=25%`、`MemoryMax=256M` 和
磁盘使用率阈值；GCP/Azure 的 1GB VPS 不安排备份任务。手工验证：

```bash
sudo VPS_PROFILE=aws bash scripts/mem0_backup.sh backup --format json
sudo VPS_PROFILE=aws bash scripts/mem0_backup.sh verify --format json
sudo VPS_PROFILE=aws bash scripts/mem0_backup.sh restore-smoke --yes --format json
```

`restore-smoke` 只恢复到临时数据库并随后删除，不会覆盖生产库。

全局命令 `/usr/local/bin/ops` 是轻量启动器，只定位本机 vps_sysops 目录并执行
`ops.sh`，不驻留进程、不复制配置和凭据。

## GCP Hermes Agent 服务管理

GCP 的 `ops` 菜单项 19 委托主机现有的 `/usr/local/bin/agent-ctl`，不重复实现
systemd 控制逻辑。也可以直接调用：

```bash
bash scripts/agent_ctl.sh status
bash scripts/agent_ctl.sh restart
bash scripts/agent_ctl.sh log 100
```

Azure/AWS profile 不显示该菜单项；在未安装 `agent-ctl` 的主机上，脚本会明确提示
不可用，不会误操作其他服务。

## 注意事项

- `01_harden.sh` **不会自动禁用** root 登录和密码登录，避免误操作把自己锁在外面。
  确认已有可用的 SSH 密钥登录账号后，再按脚本末尾提示手动开启。
- `03_monitor.sh` 支持飞书机器人 Webhook 告警，在 `config/ops.conf` 中填入 `FEISHU_WEBHOOK` 即可；
  留空则只在本地/日志输出。
- 所有脚本均为幂等设计（可重复运行），已安装的组件会自动跳过。
- 首次运行前建议先在测试环境或完成本机一致性备份后验证；不要为了运行工具包默认创建收费云快照。
