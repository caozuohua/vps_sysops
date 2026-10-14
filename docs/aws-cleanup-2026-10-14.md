# AWS 降级准备：2026-10-14

用户确认保留 Mem0 和 sysops，只清理其他项目。本次未修改 EC2 规格、卷、
公网 IP 或计费资源。AWS CLI 登录过期，无法核实赠金余额与实例规格。

## 代码保全

- Luck Agent 未提交代码保存到 `caozuohua/luck-agent` 的
  `archive/aws-pre-downgrade-20261014`，提交
  `c3d1a78fe0d755f4ddd7eaa46d82e6b73399684f`，本机通过 SSH Git 身份推送，
  `git ls-remote` 验证一致。个人 `soul/MEMORY.md` 不公开，仅存本机备份。
- AWS sysops 未推送提交和部署差异保存到 `caozuohua/vps_sysops` 同名归档分支，
  提交 `d05afe5ad0492de208b2e514fbc8a9a70e54bd2a`，远端 SHA 已核验。
  该分支用于恢复，不合并覆盖 main。
- agent-framework-lab、presales-agent-skills、博客 checkout 均为干净状态；
  fetch 后分别落后远端 1、3、13 个提交，无需要推送的本地工作。
- 无 Git 归属的 GLM 脚本、Phoenix Compose 和数据随本机备份保存，未随意发布
  到公开仓库。代码扫描未发现选中待提交文件里有明显凭据；所有 .env、数据库
  和个人记忆未新增进 Git 提交。

## 备份

本机目录：`D:\Geek\aws-retirement-2026-10-14`，NTFS ACL 仅当前用户、SYSTEM、
Administrators 可访问。备份未加密，需按敏感数据保管，不得上传公开仓库。

- `projects-and-data.tar.gz`，约 44 MiB，包含完整项目源码、Git 元数据、SQLite
  数据库、个人记忆、运行记录、.env、GLM 配置、服务 unit 和 Phoenix 数据卷。
  生成前已停服务和 Phoenix，排除可重建的 venv/.venv/node_modules 等依赖。
- SHA-256：`44cad6cdf8bb86ed343ebd17bfa98f26e982e647e536184efbbcad0243d4960f`，
  AWS/Windows 一致，tar 目录验证通过并确认关键数据库/个人记忆/配置在内。
- Luck Agent / sysops 完整 Git bundle 及本机 bare repository 也位于此目录。
- AWS 暂保留 `/var/backups/aws-pre-downgrade-20261014/projects-and-data.tar.gz`
  第二副本（0600），恢复时先解压到临时目录审阅，勿直接覆盖线上文件。

## 已清理

移除 `/opt/luck-agent`、`/opt/glm-quota-runner`、ubuntu 下的
agent-framework-lab、agent-framework-lab-evidence-final、presales-agent-skills、
caozuohua.github.io、phoenix，以及这些项目的专用配置目录。
Luck Agent service 和 GLM service/timer 已停用并移除。
Phoenix 容器、专属数据卷 `phoenix_phoenix_data` 和镜像
`arizephoenix/phoenix:version-20.4.0` 已删除。
OAuth Funnel `/oauth/lark/callback` 已关闭，现为 No serve config；
UFW 的 tailscale0 TCP 6006/4317（含 IPv6）规则已删除。

## 保留与验证

Mem0 API、Dashboard、PostgreSQL 三个容器均 healthy；API /docs 与 Dashboard
/api/health 均 200，数据库备份校验通过。
SSH、Tailscale、Docker、monitor timer、Mem0 backup timer 均 active；无 failed unit。
sysops 服务账号 luck-agent 保留，因为 `/opt/vps_sysops` 仍由该账号持有。
Codex CLI、会话、tmux、SSH 密钥和 Tailscale 身份未删除。
根盘使用率从约 75% 降到 60%，可用空间从 4.8 GiB 增至 7.4 GiB；
可用内存从约 2.2 GiB 增至 2.7 GiB。

后续降级应先恢复 AWS CLI 登录核实赠金与目标规格，Mem0 仍需要运行容量。
