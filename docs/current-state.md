# 当前 VPS 与网络状态

最后核验：2026-08-20。本文只记录可公开的基础设施事实；密钥、Token、`.env`、
x-ui 秘密路径、数据库和 Tailscale 状态文件不得提交到仓库。

## 主机清单

| 主机 | 云平台 / 系统 | 公网 IPv4 | Tailscale IPv4 | 管理入口 |
|---|---|---|---|---|
| `gcp-free-vps-oregon` | GCP / Ubuntu 26.04 LTS / kernel 7.0 | `35.212.145.19`（静态地址 `ip-free-standard-oregon`） | `100.101.90.114` | 公网密钥 SSH（应急）或 Tailscale 原生 SSH |
| `az-free-vm` | Azure Central US / Ubuntu 24.04 LTS / ARM64 | 无 | `100.115.42.83` | 仅 Tailscale 原生 SSH |
| `aws-codex-vps` | AWS / Ubuntu 24.04.4 LTS / x86_64 | `54.166.122.61` | `100.112.88.72` | 公网密钥 SSH 或 Tailscale 原生 SSH |

Windows 节点为 `desktop-97l4bfc` / `100.124.35.84`；手机节点为
`iphone-12` / `100.70.46.122`。

## 云防火墙与监听边界

### GCP

- 公网允许：TCP `22`、`80`、`443`。
- GCP VPC 高优先级拒绝：TCP `3000`、`50404`、`44301`。
- 主机 `iptables-hardening.service` 额外阻止公网接口 `ens4:50404`，并在
  `DOCKER-USER` 阻止直接访问容器端口 `3000`。
- newAPI 只发布到 `127.0.0.1:3000`；A2A 只监听
  `100.101.90.114:8765`。
- `/opt/vps_sysops` 已部署 Mem0 服务级运维入口；GCP profile 通过 Tailscale
  检查 AWS Mem0 API，系统级 Hermes/A2A 服务保持 active。

### Azure

- 订阅 `Azure subscription 1`（`033bf65c-e257-4ead-bec5-58361a3d0d3e`）中，
  活跃资源位于资源组 `az-free-vm_group`。
- VM `az-free-vm` 使用 `Standard_B2pts_v2`；OS 磁盘为 64 GiB Premium SSD
  LRS（`Premium_LRS`，P6）。用户于 2026-08-10 在 Azure 门户选择了标注为
  免费层级的磁盘选项；实际免费额度和计费状态仍应以订阅账单实时核验为准。
- NIC `az-free-vmVMNic`、VNet `az-free-vmVNET`、NSG `az-free-vm-nsg`；
  私网地址 `10.0.0.4`，没有公网 IP。
- NSG 没有自定义公网入站允许规则，使用默认拒绝入站；主机 UFW 仅允许
  `tailscale0` 上的 TCP `22` 和 `8765`。
- 从公网实测 TCP `22`、`80`、`443`、`8765` 均不可达。
- SSH 与 A2A 分别监听本机 `22` 和 Tailscale 地址 `100.115.42.83:8765`，
  但只有 tailnet ACL 允许的节点可访问。
- 旧 VM `az-vps`、资源组 `az-vps_group` 及旧公网 IP 已于 2026-08-10
  永久删除，不再属于当前拓扑。
- `/home/caozuohua/vps_sysops` 已部署 Mem0 服务级运维入口；Hermes 和用户级
  A2A 服务保持 active，A2A `/healthz` 实测返回 HTTP 200。

### AWS

- 主机名 `aws-codex-vps`，服务用户 `ubuntu`；实时主机检查确认
  `ssh`、`tailscaled` 正常运行。
- 公网 SSH `54.166.122.61:22` 仍可用；Tailscale 地址为
  `100.112.88.72`，三台 VPS 的 TCP 22 互访已实测通过。
- UFW 已启用：默认拒绝入站，仅允许 `tailscale0` 上的 TCP `22`、Mem0
  Dashboard 的 `3000` 和 Mem0 API 的 `8888`；SSH 收紧后已重新实测连接成功。
- 已安装并启用 Docker `29.1.3` 与 Compose `2.40.3`。
- Mem0 Server `v2.0.18` 已固定到官方源码 commit
  `c427a453a89c5a3fee73cdb2e4c4df6a651e1692`，部署目录为 `/opt/mem0`。
  PostgreSQL/pgvector 已启动并健康；API 仅绑定
  `100.112.88.72:8888`，数据库不发布主机端口。`.env` 已配置 NIM
  OpenAI-compatible base URL、LLM `nvidia/nvidia-nemotron-nano-9b-v2` 与
  embedding `nvidia/nemotron-3-embed-1b`；实测 NIM LLM 返回 200，embedding
  返回 2048 维。部署配置显式使用 2048 维并关闭 pgvector HNSW（HNSW 上限
  为 2000 维），已实测 Mem0 embedding 调用和 pgvector collection 创建成功。
  Dashboard 已构建并运行，健康端点为
  `http://100.112.88.72:3000/api/health`。认证保持开启，
  admin/API key bootstrap 已完成。Tailscale ACL 已发布并包含 GCP/Azure 到 AWS
  的 TCP `8888`；从两台 Hermes 主机实测 API 认证、读写和跨主机检索均返回
  HTTP 200。
- `/opt/vps_sysops` 已部署并按 AWS Compose 实际路径配置为
  `/opt/mem0/server/docker-compose.yaml`；`scripts/mem0.sh status`、
  `health`、`smoke` 均已验证。专用 smoke 认证文件位于
  `/etc/vps-sysops/mem0.env`，权限为 `0600`，不进入仓库。
- 三台 VPS 均已注册 `/usr/local/bin/ops` 全局入口；它只转发到本机
  `vps_sysops/ops.sh`，不启动常驻进程，也不复制凭据。
- GCP 的 `ops` 菜单增加 Hermes Agent 服务管理入口（19），委托现有
  `/usr/local/bin/agent-ctl` 管理 `hermes-gateway.service`，支持状态、启动、
  停止、重启、日志和虚拟环境检查；Azure/AWS 不显示该 profile 专属菜单项。
- 三台 VPS 已安装轻量 systemd monitor timer：GCP
  `vps-ops-monitor-gcp.timer`、Azure `vps-ops-monitor-azure.timer`、AWS
  `vps-ops-monitor-aws.timer`，每 5 分钟运行一次 oneshot，限制为
  `CPUQuota=10%`、`MemoryMax=128M`、`Nice=10`，不常驻后台进程。
- 仅 AWS 启用 `vps-ops-backup-aws.timer`，每天凌晨随机延迟执行一次 Mem0
  PostgreSQL custom-format dump，写入 `/var/backups/vps-sysops/mem0`，限制为
  `CPUQuota=25%`、`MemoryMax=256M`、`Nice=19`、I/O idle，并保留 7 天。
  备份脚本会检查磁盘使用率、SHA-256 和 `pg_restore -l`；`restore-smoke`
  只操作临时数据库。GCP/Azure 不安排这项任务，以控制 1GB VPS 资源占用。

## Hermes 共享记忆接入

- GCP `hermes-lite` 与 Azure Hermes 均已启用 `memory.provider=mem0`，通过
  AWS Mem0 Server 的 `http://100.112.88.72:8888` 访问。
- 两个 Agent 使用相同的 `user_id=personal`，分别以
  `agent_id=gcp-hermes`、`agent_id=azure-hermes` 标记写入来源；API key
  分开配置且不写入仓库。
- GCP 原有 Mem0 插件只支持云端，已同步自托管 HTTP backend 并保留了远端
  回滚副本；两台 Hermes 服务均已重启并读取到自托管 provider 配置。
- 双向临时 smoke test 已完成：GCP 写入由 Azure 检索、Azure 写入由 GCP 检索，
  两条临时记录均已删除，清理后的标记检索结果为 `0`。
- 三台 VPS 的 `vps_sysops` Mem0 smoke 均通过：临时写入、检索、删除均返回
  HTTP 200；三台的 `03_monitor.sh` 均返回“状态正常”。

## Tailscale ACL

实际策略的脱敏、可版本化副本位于
`system/tailscale/grants.hujson`。2026-08-20 已发布并验证如下矩阵：

| 来源 | 目标 | 允许 | 拒绝 / 未授权 |
|---|---|---|---|
| Windows、iPhone | GCP | TCP `22`、`50404` | `8765` 及其他端口 |
| Windows、iPhone | Azure | TCP `22` | `8765` 及其他端口 |
| GCP | Azure | TCP `22`、`8765` | 其他端口 |
| GCP | AWS | TCP `22`、`8888`（Mem0） | 其他端口 |
| Azure | GCP | TCP `22`、`8765` | `50404` 及其他端口 |
| Azure | AWS | TCP `22`、`8888`（Mem0） | 其他端口 |
| AWS | GCP、Azure | TCP `22` | 其他端口 |

使用的是 Tailscale 网络上的原生 OpenSSH，不启用 Tailscale SSH 策略。三台 VPS
的用户级 SSH 配置已加入 `gcp-ts`、`az-ts`、`aws-ts` 互访别名，按对端使用
独立 ED25519 密钥；公钥只追加到目标用户的 `authorized_keys`，未覆盖已有条目。

## GCP 业务链路

公网 `443` 由 nginx stream `ssl_preread` 按 SNI 分流：

- `api.caozuohua.cloud-ip.cc` → 本机 TLS nginx `127.0.0.1:8443`
  → newAPI `127.0.0.1:3000`。
- `xui.caozuohua.cloud-ip.cc` → 本机 TLS nginx `127.0.0.1:8443`
  → x-ui 管理端口 `127.0.0.1:50404`；根路径返回 404，真实秘密路径不入库。
- 其他 SNI → Xray `127.0.0.1:44301`，这是科学上网链路，不能被普通 Web
  反代或防火墙清理误伤。

当前关键版本与状态：

- newAPI `v1.0.0-rc.21`，容器端口仅回环，公共注册和密码注册关闭。
- x-ui `0.3.2` 与 Xray 进程正常。
- Docker `29.6.2`，Tailscale `1.98.9`。
- `ssh`、`tailscaled`、`docker`、`nginx`、`x-ui`、`new-api`、
  `hermes-a2a-bridge`、`iptables-hardening` 与 `certbot.timer` 均已启用并运行。
- Google Ops Agent 在 Ubuntu 26.04 上保持 masked；当前 Google 支持矩阵尚未包含
  26.04，不能强制启动旧构建。

## A2A

- GCP：系统级 `hermes-a2a-bridge.service`，监听 `100.101.90.114:8765`。
- Azure：用户 `caozuohua` 的用户级 `hermes-a2a-bridge.service` 和
  `hermes-gateway.service`，A2A 监听 `100.115.42.83:8765`。
- 正确健康端点为 `/healthz`；根路径和 `/health` 返回 404 属于预期。
- 工具调用在部署配置中关闭；代码和策略见 `a2a-bridge/`。

## 备份策略

- 不创建收费的 GCP 快照或云备份。
- 发行版升级前的一致性本机备份位于 `/var/backups/codex-preupgrade-*`。
- 日常使用 `VPS_PROFILE=gcp|azure|aws scripts/04_backup.sh`：归档以 `0600`
  权限写入 `/var/backups/vps-sysops`，并先对 newAPI、x-ui 和 A2A SQLite
  数据库执行在线 `.backup` 与完整性检查。
- Mem0 PostgreSQL 使用 `scripts/mem0_backup.sh` 单独备份；只在 AWS 的 systemd
  timer 中启用，不在 GCP/Azure 上增加后台备份负载。备份文件为 `0600`，默认
  保留 7 天；定时服务使用 flock 防止重入。
- 本机备份不等于异地灾备；若以后接受额外费用，应重新评估加密异地备份。

## 例行验证

```bash
# 三台主机会按 hostname 自动选择 profile，也可显式指定
VPS_PROFILE=gcp bash scripts/03_monitor.sh
VPS_PROFILE=gcp bash scripts/11_network.sh
VPS_PROFILE=azure bash scripts/03_monitor.sh
VPS_PROFILE=azure bash scripts/11_network.sh
VPS_PROFILE=aws bash scripts/03_monitor.sh
VPS_PROFILE=aws bash scripts/11_network.sh
bash scripts/mem0.sh status --format json
sudo VPS_PROFILE=aws bash scripts/mem0_backup.sh verify --format json
```

修改 ACL、云防火墙、nginx stream、x-ui/Xray 端口或 newAPI 镜像 tag 后，必须同步
更新本文并重新验证允许与拒绝路径。
