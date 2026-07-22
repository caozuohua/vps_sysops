# Contributing

感谢你考虑为本项目贡献代码或文档。本文档说明如何参与贡献。

## 开始之前

- 阅读 [README.md](README.md) 了解项目架构与约定。
- 阅读 [SECURITY.md](SECURITY.md)，了解安全边界和禁止提交的内容类型。
- 对于较大的改动，建议先开 Issue 讨论方案，再动手写代码。

## 开发环境

本项目的脚本在 **Ubuntu 24.04+** 和 **bash 4.4+** 下开发和测试。没有额外的构建工具依赖。

```bash
# 克隆仓库
git clone https://github.com/caozuohua/vps_sysops.git
cd vps_sysops

# 赋予执行权限
chmod +x ops.sh scripts/*.sh

# 运行 smoke test（无需 root，无副作用）
bash tests/smoke.sh
```

## 贡献流程

1. Fork 本仓库，基于 `main` 创建功能分支：

   ```bash
   git checkout -b feat/your-feature-name
   ```

2. 遵循下方的代码风格规范完成修改。

3. 如涉及新功能，更新 `README.md` 的模块速查表和配置项说明；如涉及 bug 修复或破坏性变更，在 `CHANGELOG.md` 的 `[Unreleased]` 节追加记录。

4. 提交代码，使用 [约定式提交](https://www.conventionalcommits.org/zh-hans/) 格式：

   ```
   feat(scripts): 为 07_resources 增加 JSON 输出模式
   fix(monitor): 修复用户级 systemd 探测逻辑
   docs: 更新 crontab 示例
   refactor(backup): 提取 SQLite 备份逻辑为独立函数
   ```

5. 推送分支并开 Pull Request，标题遵循同样的约定式格式。

## 代码风格

### Shell 脚本

- 脚本头部固定使用 `#!/usr/bin/env bash` 和 `set -euo pipefail`。
- 每个 `scripts/*.sh` 顶部必须 `source "${SCRIPT_DIR}/../config/ops.conf"`，不得硬编码配置值。
- 颜色与日志函数（`log` / `warn` / `error` / `title` / `section`）每个脚本自带，**不得**依赖其他脚本中的同名函数。
- 主逻辑定义为 `cmd_<模块名>` 函数，末尾直接调用——使脚本既可被 `ops.sh` source，也可独立执行。
- 所有脚本支持 `-h` / `--help` 参数，打印用法后立即退出。
- 变量引用加双引号，防止路径含空格时出错：`"${VAR}"` 而非 `$VAR`。
- 新增脚本编号不得重排既有编号，按序追加即可。
- 通过 `shellcheck` 静态检查（`shellcheck scripts/your_script.sh`），消除 SC2086、SC2046 等常见警告。

### Python（a2a-bridge/）

- 遵循 PEP 8，使用 4 空格缩进。
- 类型注解对新代码为必须项。
- 新增依赖须更新 `a2a-bridge/` 下的依赖清单（如有）。

## 不得提交的内容

以下内容由 `.gitignore` 和 `a2a-bridge/.gitignore` 排除，**绝对不得提交**：

| 类型 | 示例 |
|------|------|
| 秘密与凭证 | `.env`、`*.key`、`*.pem`、`*token*` |
| 本机 profile | `config/hosts/*.local.conf` |
| 数据库与运行时状态 | `*.db`、`*.sqlite`、`state/` |
| 备份文件 | `*.tar.gz`、`*.sha256` |
| x-ui 秘密路径 | `XUI_WEB_BASE_PATH` 的实际值 |
| TLS 私钥 / 证书 | Let's Encrypt 证书、私钥 |

提交前请运行 `git diff --cached` 仔细检查，确认无上述内容。

## 报告 Bug

请使用 GitHub Issue，选择 **Bug Report** 模板并填写完整信息。
对于安全漏洞，请参考 [SECURITY.md](SECURITY.md) 通过私下渠道报告，**不要公开 Issue**。

## 提问与讨论

一般性问题请开 GitHub Discussions 或 Issue。
