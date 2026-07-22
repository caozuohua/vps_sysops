# Security Policy

## Scope

本仓库是一套 Shell + Python 的 VPS 运维工具包。以下内容在 scope 内：

- `ops.sh` 及 `scripts/` 下各功能模块的安全缺陷（命令注入、权限提升、信息泄露等）
- `a2a-bridge/` 中桥接服务和 MCP 适配器的安全问题
- `config/ops.conf` 及 profile 加载逻辑中的路径穿越、任意代码执行
- `scripts/01_harden.sh` 加固逻辑的绕过或回退

以下内容**不在 scope 内**：

- 与本工具包无关的 VPS 系统本身漏洞
- 第三方工具（fail2ban、UFW、Nginx、x-ui）自身的 CVE
- 因用户错误配置（如使用弱密码、将面板端口暴露公网）导致的风险

## 版本支持

| 分支 | 支持状态 |
|------|----------|
| `main` | 当前维护，接受安全修复 |
| 历史 tag | 不维护 |

## 报告漏洞

**请勿通过公开 Issue 报告安全漏洞。**

请通过以下方式私下披露：

1. 使用 GitHub 的 [Private Security Advisory](https://github.com/caozuohua/vps_sysops/security/advisories/new) 功能提交。
2. 或发送邮件至仓库所有者（见 GitHub Profile）。

报告内容请包含：

- 受影响的脚本或模块
- 漏洞类型（命令注入 / 权限提升 / 信息泄露等）
- 复现步骤（如适用）
- 建议的修复方案（可选）

## 设计安全边界

本工具包在设计上遵循以下安全原则，贡献者须一并遵守：

- **不提交任何秘密**：`.env`、Token、私钥、TLS 证书、数据库文件、x-ui 秘密路径一律由 `.gitignore` 排除。
- **本机备份不含云快照**：备份脚本只在 VPS 本机存储，不默认写入云存储，避免意外产生费用或暴露数据。
- **最小权限原则**：需要 root 的操作在模块内部明确说明并按需 `sudo`，不对整个脚本全程 root 化。
- **幂等与只读诊断**：所有诊断模块不修改系统状态；加固/安装模块在 README 和 `--help` 中明确标注副作用。
- **白名单保护**：`sync_fail2ban_to_ufw.sh` 内置回环、私有网段、管理员 IP 白名单，防止误封自身。

## 已知限制

- `config/hosts/*.local.conf` 含敏感本机配置，已由 `.gitignore` 排除，**不得提交**。
- `docs/current-state.md` 仅记录可公开的基础设施事实（IP、端口矩阵）；私钥、Token 不得写入该文件。
- 本工具包不提供证书或密钥管理，TLS 私钥由 Certbot 管理，不纳入版本控制。
