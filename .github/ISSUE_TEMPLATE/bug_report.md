---
name: Bug 报告
about: 报告一个错误或非预期行为
title: "fix: "
labels: bug
assignees: ''
---

## 描述

<!-- 清晰简洁地描述 bug 是什么 -->

## 复现步骤

1. 执行命令：`bash scripts/XX_xxx.sh`
2. 配置了哪些 `ops.conf` 变量
3. 出现了什么错误

## 预期行为

<!-- 描述你期望发生什么 -->

## 实际行为

<!-- 描述实际发生了什么，附上错误输出 -->

```
粘贴终端输出
```

## 环境信息

- OS：`lsb_release -ds` 输出
- Bash 版本：`bash --version` 输出
- 云平台：GCP / Azure / 其他
- `VPS_PROFILE`：gcp / azure / 空（自动识别）
- 受影响的脚本：`scripts/XX_xxx.sh`

## 其他上下文

<!-- 其他有助于诊断的信息，例如 `journalctl` 相关日志片段 -->

---

> **安全提醒**：如果这是一个安全漏洞，请**不要**在此公开报告，参考 [SECURITY.md](../../SECURITY.md) 通过私下渠道披露。
