# vps_sysops
GCP Ubuntu VPS 全面运维脚本，包含 12 个功能模块

'''

## 命令功能

-- overview  主机信息 + GCP 元数据（实例ID、机型、可用区、IP）

-- resources CPU 使用率、内存、磁盘空间、I/O、网络接口

-- processes Top CPU/内存进程、僵尸进程检测

-- services  关键服务状态（nginx、docker、fail2ban 等）+ 监听端口

-- logssyslog 错误、认证失败、OOM 事件、大日志文件

-- securityUFW 防火墙、SSH 暴破 IP 统计、SUID 文件、sudo 用户

-- network   路由、DNS、GCP 端点连通性测试、流量统计

-- disk      磁盘使用 / inode、大文件 Top20、smartctl 健康

-- updates   可用更新 & 安全补丁（AUTO_UPDATE=true 自动安装）

-- backup    备份 ssh/nginx/mysql 等配置到 /var/backups/sysopstunesysctl 参数检查 + 高并发/数据库调优建议

-- report    全量报告输出到 /tmp/sysops_reports/

'''


快速上手：
bash# 上传到服务器
scp sysops.sh user@your-gcp-ip:~/

# 添加执行权限
chmod +x sysops.sh

# 查看系统概览（无需 root）
bash sysops.sh overview

# 安全审计（需要 root）
sudo bash sysops.sh security

# 生成完整报告
sudo bash sysops.sh report
脚本会自动适配 GCP 元数据 API，能直接读取实例 ID、机型、可用区等信息，在非 GCP 环境下也可优雅降级。