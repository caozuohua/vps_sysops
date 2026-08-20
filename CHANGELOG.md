# Changelog

本文档遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## [Unreleased]

### Planned
- 告警推送支持企业微信 / Telegram Bot
- `--format=json` 结构化输出模式（供 Grafana / 自建 API 消费）
- 多机批量执行框架（`--hosts=hosts.txt`）
- GCS 远程备份 + 备份验证

---

## [2.2.0] - 2026-07-18

### Added
- `a2a-bridge/`：GCP ↔ Azure 间私有 Hermes A2A 桥接服务与 MCP 适配器
  - `bridge.py`：A2A 桥接主服务，仅绑定 Tailscale 地址
  - `a2a_mcp.py`：MCP 协议适配器
  - `mcp_probe.py` / `mcp_probe_safeenv.py`：探针工具
  - `hermes-a2a-bridge-{gcp,azure}.service`：systemd unit 模板
  - `A2A_POLICY.md`：服务安全边界说明
  - `AZURE-1G-DOWNGRADE.md`：Azure 1G 降配操作清单
- `tests/smoke.sh`：Shell / profile / Python 与 SQLite 语法 smoke test
- `tests/backup_smoke.sh`：SQLite 在线备份、完整性校验与权限验证
- `system/gcp/`：GCP 当前线上配置脱敏副本纳入版本管理
  - APT 源（Docker / Tailscale / GitHub CLI / Cloudflared）
  - SSH 加固配置（禁 Agent/远程转发/tunnel）
  - sysctl 网络调优（fq + BBR + swappiness）
  - systemd unit：newAPI、iptables-hardening、A2A Tailscale wait
- `system/tailscale/grants.hujson`：tailnet 最小权限 ACL 策略
- `config/hosts/gcp.conf` / `config/hosts/azure.conf`：主机 profile 自动选择

### Changed
- `scripts/03_monitor.sh`：Hermes 网关按系统级 → 用户级两级自动检测
- `scripts/04_backup.sh`：profile 覆盖 GCP / Azure 各自的 SQLite 数据库列表
- `scripts/08_services.sh`：按 `MONITOR_USER` 查用户级 systemd unit
- `scripts/11_network.sh`：增加 Tailscale ACL 探测矩阵（allow / deny targets）

### Fixed
- `a2a-bridge/bridge.py`：忽略不支持的 delegated toolsets，避免启动报错

---

## [2.1.0] - 2026-07 (模块化重构 + 双云识别 + 暴力破解加固)

### Added
- `scripts/14_web_stack.sh`：x-ui / Nginx / Let's Encrypt Web 栈管理
  - 支持 `--install`、`--xui-path`、`--issue`、`--status`、`--renew --dry-run`
  - Nginx 反代，x-ui 只绑定 `127.0.0.1`，根路径返回 404
- `scripts/sync_fail2ban_to_ufw.sh`：Fail2Ban → UFW 双向同步守护
  - 读取 fail2ban 实际封禁列表，自动 `ufw deny`；解封后清理对应规则
  - 内置白名单（回环 / 私有网段 / 管理员 IP）
- `system/etc/`：加固配置纳入版本管理
  - `fail2ban/jail.local`：强化 maxretry / bantime / recidive
  - `fail2ban/action.d/ufw-simple.conf`：极简 UFW action
  - `ssh/sshd_config.d/99-bruteforce.conf`：MaxAuthTries=3
  - `systemd/system/failsync.{service,timer}`：每 30s 触发同步
- `ops.sh` 菜单项 16 & 17：交互式运行所有模块、Web 栈管理入口
- `.gitattributes`：统一换行符处理

### Changed
- 重构为模块化架构：`ops.sh` 作为统一调度入口，逻辑拆分到 `scripts/` 下 16 个独立脚本
- `config/ops.conf`：增加 x-ui 相关配置项（`XUI_DOMAIN`、`XUI_PANEL_PORT`、`XUI_WEB_BASE_PATH` 等）
- `scripts/05_overview.sh`：同时识别 GCP（`metadata.google.internal`）与 Azure（IMDS `169.254.169.254`），非云环境降级为 `ifconfig.me`
- `scripts/16_report.sh`：汇聚所有模块输出，写入 `REPORT_DIR`

---

## [2.0.0] - 2026-06 (系统层加固配置纳入版本管理)

### Added
- `system/` 目录：将 `/etc` 和 systemd 下的加固配置复制为可版本化副本，保持原绝对路径结构
- `docs/current-state.md`：已验证的公网 IP、Tailscale IP、端口矩阵、服务链路和备份策略运维事实清单

### Changed
- README 增加系统层配置部署说明与 crontab 建议配置

---

## [1.0.0] - 2025 (初始版本)

### Added
- `sysops.sh`：单文件 581 行，涵盖 12 个功能模块（overview / resources / processes / services / security / logs / network / disk / updates / backup / tune / report）
- GCP 原生感知：通过 `metadata.google.internal` 自动识别云环境
- 无外部依赖：标准 Linux 工具栈，可选工具优雅跳过
- ANSI 终端彩色输出

[Unreleased]: https://github.com/caozuohua/vps_sysops/compare/main...HEAD
[2.2.0]: https://github.com/caozuohua/vps_sysops/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/caozuohua/vps_sysops/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/caozuohua/vps_sysops/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/caozuohua/vps_sysops/releases/tag/v1.0.0
