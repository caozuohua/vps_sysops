# 当前 VPS 与网络状态

最后核验：2026-07-18。本文只记录可公开的基础设施事实；密钥、Token、`.env`、
x-ui 秘密路径、数据库和 Tailscale 状态文件不得提交到仓库。

## 主机清单

| 主机 | 云平台 / 系统 | 公网 IPv4 | Tailscale IPv4 | 管理入口 |
|---|---|---|---|---|
| `gcp-free-vps-oregon` | GCP / Ubuntu 26.04 LTS / kernel 7.0 | `35.212.145.19`（静态地址 `ip-free-standard-oregon`） | `100.101.90.114` | 公网密钥 SSH（应急）或 Tailscale 原生 SSH |
| `az-vps` | Azure / Ubuntu 24.04 LTS | `52.225.28.230`（PIP 保留，无公网入站） | `100.87.159.14` | 仅 Tailscale 原生 SSH |

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

### Azure

- NSG `az-vps-nsg` 没有自定义入站允许规则，使用默认拒绝入站。
- 从公网实测 TCP `22`、`80`、`443`、`8765` 均不可达。
- SSH 与 A2A 分别监听本机 `22` 和 Tailscale 地址 `100.87.159.14:8765`，
  但只有 tailnet ACL 允许的节点可访问。

## Tailscale ACL

实际策略的脱敏、可版本化副本位于
`system/tailscale/grants.hujson`。2026-07-18 验证矩阵如下：

| 来源 | 目标 | 允许 | 拒绝 / 未授权 |
|---|---|---|---|
| Windows、iPhone | GCP | TCP `22`、`50404` | `8765` 及其他端口 |
| Windows、iPhone | Azure | TCP `22` | `8765` 及其他端口 |
| GCP | Azure | TCP `22`、`8765` | 其他端口 |
| Azure | GCP | TCP `22`、`8765` | `50404` 及其他端口 |

使用的是 Tailscale 网络上的原生 OpenSSH，不启用 Tailscale SSH 策略。两台 VPS
互访别名为 GCP 上的 `az-ts` 和 Azure 上的 `gcp-ts`，均使用独立密钥。

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
  `hermes-gateway.service`，A2A 监听 `100.87.159.14:8765`。
- 正确健康端点为 `/healthz`；根路径和 `/health` 返回 404 属于预期。
- 工具调用在部署配置中关闭；代码和策略见 `a2a-bridge/`。

## 备份策略

- 不创建收费的 GCP 快照或云备份。
- 发行版升级前的一致性本机备份位于 `/var/backups/codex-preupgrade-*`。
- 日常使用 `VPS_PROFILE=gcp|azure scripts/04_backup.sh`：归档以 `0600`
  权限写入 `/var/backups/vps-sysops`，并先对 newAPI、x-ui 和 A2A SQLite
  数据库执行在线 `.backup` 与完整性检查。
- 本机备份不等于异地灾备；若以后接受额外费用，应重新评估加密异地备份。

## 例行验证

```bash
# 两台主机会按 hostname 自动选择 profile，也可显式指定
VPS_PROFILE=gcp bash scripts/03_monitor.sh
VPS_PROFILE=gcp bash scripts/11_network.sh
VPS_PROFILE=azure bash scripts/03_monitor.sh
VPS_PROFILE=azure bash scripts/11_network.sh
```

修改 ACL、云防火墙、nginx stream、x-ui/Xray 端口或 newAPI 镜像 tag 后，必须同步
更新本文并重新验证允许与拒绝路径。
