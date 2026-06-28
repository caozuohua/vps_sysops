# vps_sysops

GCP Ubuntu VPS 全面运维脚本，12 个功能模块，一键巡检、安全审计、自动备份。

## Features

| Module | Description | Root |
|--------|-------------|------|
| `overview` | 主机信息 + GCP 元数据（实例ID、机型、可用区、IP） | ❌ |
| `resources` | CPU 使用率、内存、磁盘空间、I/O、网络接口 | ❌ |
| `processes` | Top CPU/内存进程、僵尸进程检测 | ❌ |
| `services` | 关键服务状态（nginx、docker、fail2ban 等）+ 监听端口 | ❌ |
| `logs` | syslog 错误、认证失败、OOM 事件、大日志文件 | ✅ |
| `security` | UFW 防火墙、SSH 暴破 IP 统计、SUID 文件、sudo 用户 | ✅ |
| `network` | 路由、DNS、GCP 端点连通性测试、流量统计 | ❌ |
| `disk` | 磁盘使用 / inode、大文件 Top20、smartctl 健康 | ❌ |
| `updates` | 可用更新 & 安全补丁（`AUTO_UPDATE=true` 自动安装） | ✅ |
| `backup` | 备份 ssh/nginx/mysql 等配置到 `/var/backups/sysops` | ✅ |
| `tune` | sysctl 参数检查 + 高并发/数据库调优建议 | ❌ |
| `report` | 全量报告输出到 `/tmp/sysops_reports/` | ✅ |

## Quick Start

```bash
# Clone
git clone git@github.com:caozuohua/vps_sysops.git
cd vps_sysops

# Upload to your GCP VPS
scp sysops.sh user@your-gcp-ip:~/

# On the VPS:
chmod +x sysops.sh

# System overview (no root needed)
bash sysops.sh overview

# Security audit (requires root)
sudo bash sysops.sh security

# Full report
sudo bash sysops.sh report
```

## Requirements

- Ubuntu 20.04+ (tested on 22.04)
- Bash 4.0+
- For GCP metadata: must run on a GCE instance (gracefully degrades otherwise)

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_DIR` | `/var/log/sysops` | Log directory |
| `REPORT_DIR` | `/tmp/sysops_reports` | Report output directory |
| `BACKUP_DIR` | `/var/backups/sysops` | Backup storage directory |
| `AUTO_UPDATE` | `false` | Set to `true` to auto-install security updates |

## Automation

Add to crontab for daily health checks:

```bash
# Daily report at 7 AM
0 7 * * * /path/to/sysops.sh report

# Weekly security audit every Monday
0 8 * * 1 sudo /path/to/sysops.sh security
```

## License

MIT
