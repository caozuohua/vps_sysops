# VPS 运行检查：2026-10-14

检查时间：北京时间约 10:06–10:13。通过本机 SSH 读取运行状态；未执行云账单、
配额或云防火墙管理 API 审计，未重启主机，未升级其他软件或改变防火墙。

## 运行概况

| 主机 | 初始 load1 | 可用内存（初始） | 根盘 | Agent / 关键服务 |
|---|---:|---:|---:|---|
| GCP | 0.08 | 175 MiB / 952 MiB | 47% / 28 GiB | Hermes、A2A、nginx、x-ui、Docker、new-api 正常 |
| Azure | 0.00 | 407 MiB / 950 MiB | 17% / 61 GiB | 用户级 Hermes、A2A 正常 |
| AWS | 0.15 | 2205 MiB / 3812 MiB | 74%，更新后约 75% / 19 GiB | Luck Agent、Mem0、Dashboard、PostgreSQL、Phoenix 正常 |

三台均无当前 failed system unit。Hermes（GCP/Azure）及 Luck Agent 的
NRestarts 为 0（当前 systemd 生命周期内，不代表全部历史）。Azure/AWS 近七天
内核错误查询无记录；GCP 有启动时虚拟 SMBus 提示及公网 SSH 扫描错误。
dpkg --audit 未报告损坏软件包；三台均有待更新系统软件包。

## Tailscale 更新

- GCP/Azure/AWS：`1.102.3` → `1.104.1`。
- Windows：`1.102.2` → `1.104.1`，服务运行，MSI 安装日志显示 success。
- 版本由官方更新器 dry-run 查询确认。远端使用 transient systemd unit，确保
  SSH 连接中断不会中止更新；没有新增周期任务。
- GCP 自更新器因旧 tailscale.list 仅剩注释而报 unsupported source；实际官方源
  在 tailscale.sources（resolute、带 Signed-By），使用官方 APT 包成功更新。
- 升级后本机到三台 SSH、tailscaled/ssh 服务及 ops 监控再次检查。

## 服务与链路

- GCP/Azure 本机 A2A `/healthz` 均 200，互访也均 200。
- 两台访问 AWS Mem0 `/docs` 均 200；这是 HTTP 可达性检查，未重新验证
  NIM 调用、认证写入或 Agent 实际提取记忆。
- AWS Dashboard `/api/health`、Phoenix `/`、Luck Agent `8080/health` 均 200。
  `8090/health` 为 400；该端口承接 OAuth 回调，不能据此判断服务故障。
- AWS 四个容器均 healthy，PostgreSQL 无主机发布端口。
- nginx 配置校验通过，GCP 证书有效至 2026-12-28，约剩 75 天。
  Xray 回环 44301 仍监听，DOCKER-USER 对 3000 的阻挡规则仍在。
- AWS Funnel 现有公开路由仅 `/oauth/lark/callback` → `127.0.0.1:8090`。
  UFW 另允许 tailscale0 的 Phoenix 6006/4317。未修改现有路由或授权规则。
- AWS 公网 SSH 连接超时；Tailscale SSH 路径可用。GCP Tailscale status 显示
 公网端点 34.3.98.150，与旧记录 35.212.145.19 不同，需云管理 API 核实
  实例外部 IP，不能仅凭 NAT 端点认定公网地址已改变。

## 监控、备份和风险

- 三台最近 monitor 运行成功。GCP 2026-10-13 开机阶段有一次 30 秒超时，
  后续恢复；当次峰值内存 22.5 MiB。建议评估启动宽限/探测超时，避免误报。
- AWS 备份 timer enabled，最近备份 UTC 2026-10-13 03:42，约 3.6 MiB，
  checksum 与 pg_restore 格式验证通过；下一次为 UTC 2026-10-14 03:38 左右。
  本次未执行恢复演练，备份仍仅在本机。
- GCP 内存余量最小，有 swap 与近期 I/O/内存压力；升级期间采样受安装影响，
  需在日常 Agent 工作负载下持续观察。避免增加常驻监控组件。
- AWS 根盘剩约 4.8 GiB；Docker 镜像约 5 GiB，/var/lib 约 5.6 GiB，
  ubuntu 的 .local 约 1.6 GiB、.codex 约 980 MiB。未删除任何内容。
- Azure/AWS reboot-required 含内核与 libc6 更新，需安排维护窗口后重启验证。
- 现有告警闭环、离机备份、公开 OAuth 路由认证及完整云安全配置不在本次
  已证实范围；HTTP 200 不等同于端到端业务健康。
