# vps_sysops — VPS 运维工具包（模块化）

一套面向 Ubuntu VPS 的生产级 Shell 运维工具包，按**模块化架构**组织：
`ops.sh` 是统一交互入口，各功能拆到 `scripts/` 下独立、可单独调用的脚本，
共享 `config/ops.conf` 一处配置。覆盖 **16 个功能模块** —— 从基础安全加固、
运行环境部署，到系统监控、进程/服务/日志/安全/网络/磁盘诊断、更新检查、配置备份、性能调优，
再到全量报告一键生成。

## 架构规范

```
vps_sysops/
├── ops.sh                  # 总入口菜单（交互式，统一调度 scripts/ 下模块）
├── config/
│   └── ops.conf            # 全局配置：SSH 端口、放行端口、监控服务、阈值、备份、飞书告警
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
│   ├── 15_tune.sh           # 性能调优建议
│   └── 16_report.sh         # 全量报告（汇聚全部模块，输出到 REPORT_DIR）
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
| 4 | `04_backup.sh` | 备份 + 日志轮转（cron） | 部分 |
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

> 说明：模块编号沿用历史序号（06 在 07 前、13 后是 15、报告为 16），菜单已按 `scripts/` 实际文件名映射，新增脚本请勿重排既有编号。

## 使用步骤

1. 上传到服务器并解压：

   ```bash
   scp -r vps_sysops user@your-vps-ip:~/
   ssh user@your-vps-ip
   cd vps_sysops
   chmod +x ops.sh scripts/*.sh
   ```

2. 编辑 `config/ops.conf`，按需修改 SSH 端口、放行端口、**监控服务名**、备份目录、告警阈值等。

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

## 监控服务（Hermes Agent）

`config/ops.conf` 中的 `MONITOR_SERVICES` 指定需要健康检查的服务。默认监控 **Hermes Agent 网关**：

```conf
MONITOR_SERVICES="hermes-gateway.service"
```

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

本机 fail2ban v1.0.2 的 **action 执行机制整体失效**：ban 事件能产生（内存封禁 + 日志 `Ban <IP>`），
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

## 定时任务建议

健康检查每 5 分钟、备份每天凌晨、全量报告每小时：

```bash
crontab -e
```

```cron
# 每 5 分钟健康检查（含 Hermes 网关存活 + CPU/内存/磁盘阈值，异常飞书告警）
*/5 * * * * /home/youruser/vps_sysops/scripts/03_monitor.sh >> /var/log/vps-ops-monitor.log 2>&1

# 每天凌晨 3 点备份关键配置
0 3 * * * /home/youruser/vps_sysops/scripts/04_backup.sh >> /var/log/vps-ops-backup.log 2>&1

# 每小时生成全量报告（归档到 REPORT_DIR）
0 * * * * /home/youruser/vps_sysops/scripts/16_report.sh >> /var/log/vps-ops-report.log 2>&1

# 每周日凌晨 4 点自动安装安全更新
0 4 * * 0 AUTO_UPDATE=true /home/youruser/vps_sysops/scripts/13_updates.sh >> /var/log/vps-ops-update.log 2>&1
```

## 配置项说明（config/ops.conf）

| 变量 | 说明 | 默认 |
|------|------|------|
| `SSH_PORT` | SSH 端口（改非默认前先确认连通） | `22` |
| `EXTRA_ALLOW_PORTS` | 防火墙额外放行端口，逗号分隔 | `""` |
| `MONITOR_SERVICES` | 健康检查的服务名（空格分隔） | `hermes-gateway.service` |
| `CPU_THRESHOLD` / `MEM_THRESHOLD` / `DISK_THRESHOLD` | 告警阈值（%） | `90` / `85` / `85` |
| `BACKUP_SOURCES` | 备份源目录（空格分隔） | `/etc /home` |
| `BACKUP_DEST` | 备份存放目录 | `/opt/backups` |
| `BACKUP_RETAIN_DAYS` | 备份保留天数 | `7` |
| `REPORT_DIR` | 全量报告输出目录 | `/tmp/vps-ops-reports` |
| `FEISHU_WEBHOOK` | 飞书机器人 Webhook（留空仅本地输出） | `""` |

## 权限与依赖

- **无需 root**：`03_monitor` / `05_overview` / `06_processes` / `07_resources` / `08_services` /
  `09_logs` / `11_network` / `12_disk` / `15_tune`
- **需要 root**：`01_harden` / `02_setup_env` / `04_backup`（logrotate 写盘部分）/ `10_security_audit`（部分子项）/
  `13_updates` / `16_report`（security、updates 子项）

可选工具（`iostat`/`smartctl`/`dig`/`fail2ban-client`/`ufw`/`bc`）脚本会自动检测并优雅跳过。

## 注意事项

- `01_harden.sh` **不会自动禁用** root 登录和密码登录，避免误操作把自己锁在外面。
  确认已有可用的 SSH 密钥登录账号后，再按脚本末尾提示手动开启。
- `03_monitor.sh` 支持飞书机器人 Webhook 告警，在 `config/ops.conf` 中填入 `FEISHU_WEBHOOK` 即可；
  留空则只在本地/日志输出。
- 所有脚本均为幂等设计（可重复运行），已安装的组件会自动跳过。
- 首次运行前建议先在测试环境或快照后的实例上验证一遍。
