# Azure VPS 降级到 1 vCPU / 1 GB 内存执行清单

适用对象：Azure VPS。当前主要运行 Hermes Gateway、A2A Bridge、Tailscale、SSH 和安全维护服务。

## 降级前记录

- 当前 Hermes Gateway 内存约 454 MB，历史峰值约 540 MB。
- 当前 A2A Bridge 内存约 14 MB。
- 当前 Swap：2 GB。
- 记录降级前的公网 IP、DNS、SSH 配置和 Tailscale 节点状态。

## 必做配置

### Hermes Gateway

将 user service 的资源限制调整为：

```ini
MemoryHigh=500M
MemoryMax=650M
CPUQuota=80%
```

保持 `max_concurrent_sessions: 1`，不要开启并行会话。

### A2A Bridge

将 Bridge service 的资源限制调整为：

```ini
MemoryHigh=96M
MemoryMax=128M
CPUQuota=50%
TasksMax=32
```

将环境变量调整为：

```env
A2A_MAX_PENDING_TASKS=2
A2A_TASK_TTL=259200
A2A_CONTEXT_TTL=604800
```

如果不需要传输较大文件，将 artifact 单文件限制从 10 MB 降到 4 MB。

### Swap

保留 2 GB Swap；建议设置：

```ini
vm.swappiness=10
```

Swap 只用于应对瞬时峰值，不能替代实际内存。

## 可选服务裁剪

确认不需要后，可以停止并禁用：

- `fwupd.service`
- `ModemManager.service`
- `multipathd.service`
- `udisks2.service`

不要关闭：

- `tailscaled.service`
- `fail2ban.service`
- `ssh.service`
- `systemd-resolved.service`
- `unattended-upgrades.service`

## 日志和磁盘

限制 systemd journal 并清理旧日志：

```bash
journalctl --vacuum-size=100M
```

继续保留 A2A SQLite、WAL、事件日志和 artifact TTL 清理机制；确认没有把 `state/`、`__pycache__/` 或环境密钥提交到 Git。

## 降级后验证

```bash
free -h
swapon --show
systemctl --user is-active hermes-gateway.service hermes-a2a-bridge.service
curl -fsS http://<AZURE_TAILSCALE_IP>:8765/healthz
tailscale status
```

然后从 GCP 执行一次：

- Agent Card 查询
- A2A 任务提交与取消
- MCP 工具发现
- 双向回调测试

## IP 注意事项

Azure 当前没有专属静态公网 IP。降级或重建后公网 IP 可能变化：

- Tailscale 地址通常不变，前提是保留 Tailscale 状态。
- SSH、DNS、监控和公网入口若依赖公网 IP，需要更新。
- A2A 回调使用 Tailscale 地址，通常不需要修改。

## 判断是否需要进一步降级

如果降级后 Hermes 峰值持续超过 700 MB、频繁触发 OOM 或大量使用 Swap，则将 Azure 调整为低频备用节点，把主要 A2A 协作任务交给 GCP。
