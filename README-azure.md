# VPS 运维脚本工具包

适用于 Ubuntu 24.04.1 X86（Azure VPS 等）。覆盖：基础安全加固、运行环境部署、系统监控、备份与日志轮转。

## 目录结构

```
vps-ops/
├── ops.sh                  # 总入口菜单
├── config/ops.conf         # 配置文件，使用前请先编辑
└── scripts/
    ├── 01_harden.sh         # 安全加固
    ├── 02_setup_env.sh      # Docker / Python / Node 环境
    ├── 03_monitor.sh        # 健康检查（可加 cron）
    └── 04_backup.sh         # 备份 + 日志轮转（可加 cron）
```

## 使用步骤

1. 上传到服务器并解压：
   ```bash
   scp -r vps-ops user@your-vps-ip:~/
   ssh user@your-vps-ip
   cd vps-ops
   chmod +x ops.sh scripts/*.sh
   ```

2. 编辑 `config/ops.conf`，按需修改 SSH 端口、放行端口、监控服务名、备份目录等。

3. 运行菜单：
   ```bash
   ./ops.sh
   ```
   或直接执行单个脚本，例如：
   ```bash
   sudo bash scripts/01_harden.sh
   ```

## 定时任务建议

健康检查每 5 分钟一次，备份每天凌晨执行一次：

```bash
crontab -e
```

加入：
```
*/5 * * * * /home/youruser/vps-ops/scripts/03_monitor.sh >> /var/log/vps-ops-monitor.log 2>&1
0 3 * * * /home/youruser/vps-ops/scripts/04_backup.sh >> /var/log/vps-ops-backup.log 2>&1
```

## 注意事项

- `01_harden.sh` **不会自动禁用** root 登录和密码登录，避免误操作把自己锁在外面。确认已有可用的 SSH 密钥登录账号后，再按脚本末尾提示手动开启。
- `03_monitor.sh` 支持飞书机器人 Webhook 告警，在 `config/ops.conf` 中填入 `FEISHU_WEBHOOK` 即可；留空则只在本地/日志输出。
- 所有脚本均为幂等设计（可重复运行），已安装的组件会自动跳过。
- 首次运行前建议先在测试环境或快照后的实例上验证一遍。
