#!/usr/bin/env bash
# 14_web_stack.sh —— GCP Ubuntu VPS 的 x-ui / Nginx / Let’s Encrypt 运维
# 默认只读查看状态；安装、配置、申请证书和修改 x-ui 路径均需显式指定动作。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/ops.conf"

XUI_DB_PATH="${XUI_DB_PATH:-/etc/x-ui/x-ui.db}"
NGINX_SITE_NAME="${NGINX_SITE_NAME:-vps-sysops-xui}"
NGINX_AVAILABLE="/etc/nginx/sites-available/${NGINX_SITE_NAME}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${NGINX_SITE_NAME}"
ACME_ROOT="/var/www/letsencrypt"

usage() {
  cat <<EOF
用法: sudo bash scripts/14_web_stack.sh [动作]

GCP Ubuntu VPS Web 栈运维：x-ui 本地反代、Nginx、Let’s Encrypt。

动作:
  --status              查看 nginx、x-ui、证书和本地端口状态（默认）
  --install             安装 nginx、certbot 和 webroot 插件
  --configure           写入 HTTPS 反代配置（证书必须已存在）
  --issue               通过 HTTP-01 webroot 申请证书并启用 HTTPS
  --renew               执行证书续期并在成功后 reload nginx
  --renew --dry-run     只验证自动续期流程
  --xui-path PATH       设置 x-ui 的 webBasePath，并备份数据库
  -h, --help            显示本帮助

配置项来自 config/ops.conf：
  XUI_DOMAIN、XUI_PANEL_PORT、XUI_WEB_BASE_PATH、LETSENCRYPT_EMAIL
  XUI_DB_PATH、NGINX_SITE_NAME

注意：域名必须已解析到本机；GCP VPC 防火墙还必须放行 TCP 80/443。
EOF
}

require_root() {
  [[ $EUID -eq 0 ]] || { echo "请使用 sudo 或 root 权限运行此动作" >&2; exit 1; }
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "缺少命令: $1" >&2; exit 1; }
}

require_domain() {
  [[ -n "${XUI_DOMAIN:-}" ]] || { echo "请在 config/ops.conf 设置 XUI_DOMAIN" >&2; exit 1; }
  [[ "${XUI_DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "XUI_DOMAIN 格式无效" >&2; exit 1; }
  [[ "${XUI_DOMAIN}" != .* && "${XUI_DOMAIN}" != *..* ]] || { echo "XUI_DOMAIN 格式无效" >&2; exit 1; }
}

normalized_path() {
  local path="${1:-}"
  [[ "$path" == /* ]] || { echo "x-ui webBasePath 必须以 / 开头" >&2; exit 1; }
  [[ "$path" =~ ^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$ ]] || { echo "x-ui webBasePath 只允许字母、数字、_、- 和 /" >&2; exit 1; }
  [[ "$path" != / ]] || { echo "拒绝使用 / 作为 x-ui 面板路径，请设置随机路径" >&2; exit 1; }
  path="${path%/}"
  printf '%s' "$path"
}

require_web_config() {
  require_domain
  XUI_WEB_BASE_PATH="$(normalized_path "${XUI_WEB_BASE_PATH:-}")"
  [[ "${XUI_PANEL_PORT:-}" =~ ^[0-9]+$ ]] || { echo "XUI_PANEL_PORT 必须是数字" >&2; exit 1; }
  (( XUI_PANEL_PORT >= 1 && XUI_PANEL_PORT <= 65535 )) || { echo "XUI_PANEL_PORT 超出范围" >&2; exit 1; }
}

install_packages() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y nginx certbot python3-certbot-nginx
  install -d -m 0755 "$ACME_ROOT"
  systemctl enable --now nginx
}

write_http_config() {
  require_web_config
  install -d -m 0755 "$ACME_ROOT"
  cat > "$NGINX_AVAILABLE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${XUI_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root ${ACME_ROOT};
        default_type text/plain;
    }

    location / {
        return 404;
    }
}
EOF
  ln -sfn "$NGINX_AVAILABLE" "$NGINX_ENABLED"
  nginx -t
  systemctl reload nginx
}

write_https_config() {
  require_web_config
  [[ -f "/etc/letsencrypt/live/${XUI_DOMAIN}/fullchain.pem" ]] || {
    echo "证书不存在，请先执行 --issue" >&2; exit 1;
  }
  cp -a "$NGINX_AVAILABLE" "${NGINX_AVAILABLE}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  cat > "$NGINX_AVAILABLE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${XUI_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root ${ACME_ROOT};
        default_type text/plain;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl;
    server_name ${XUI_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${XUI_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${XUI_DOMAIN}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;

    location = ${XUI_WEB_BASE_PATH} {
        return 301 ${XUI_WEB_BASE_PATH}/;
    }

    location ${XUI_WEB_BASE_PATH}/ {
        proxy_pass http://127.0.0.1:${XUI_PANEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }

    location / {
        return 404;
    }
}
EOF
  ln -sfn "$NGINX_AVAILABLE" "$NGINX_ENABLED"
  nginx -t
  systemctl reload nginx
}

issue_certificate() {
  require_web_config
  [[ -n "${LETSENCRYPT_EMAIL:-}" ]] || { echo "请在 config/ops.conf 设置 LETSENCRYPT_EMAIL" >&2; exit 1; }
  install_packages
  write_http_config
  require_cmd certbot
  certbot certonly --webroot -w "$ACME_ROOT" -d "$XUI_DOMAIN" \
    --non-interactive --agree-tos --email "$LETSENCRYPT_EMAIL"
  write_https_config
  echo "证书申请并启用 HTTPS 完成: https://${XUI_DOMAIN}${XUI_WEB_BASE_PATH}/"
}

set_xui_path() {
  require_root
  require_cmd sqlite3
  [[ -f "$XUI_DB_PATH" ]] || { echo "x-ui 数据库不存在: $XUI_DB_PATH" >&2; exit 1; }
  local path="$(normalized_path "${1:-${XUI_WEB_BASE_PATH:-}}")"
  local backup="${XUI_DB_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a "$XUI_DB_PATH" "$backup"
  sqlite3 "$XUI_DB_PATH" "BEGIN; DELETE FROM settings WHERE key='webBasePath'; INSERT INTO settings(key,value) VALUES('webBasePath','$path'); COMMIT;"
  systemctl restart x-ui
  echo "x-ui webBasePath 已设置为 $path，数据库备份: $backup"
}

status() {
  echo "=== 服务 ==="
  systemctl is-active --quiet nginx && echo "nginx: active" || echo "nginx: inactive"
  systemctl is-active --quiet x-ui && echo "x-ui: active" || echo "x-ui: inactive/not-installed"
  echo "=== 本地面板端口 ==="
  ss -ltnp 2>/dev/null | grep -E ":${XUI_PANEL_PORT}([[:space:]]|$)" || echo "未发现监听端口 ${XUI_PANEL_PORT}"
  echo "=== HTTPS 配置 ==="
  [[ -L "$NGINX_ENABLED" ]] && echo "nginx site: enabled" || echo "nginx site: disabled"
  if [[ -z "${XUI_DOMAIN:-}" ]]; then
    echo "XUI_DOMAIN: 未配置"
  elif [[ -f "/etc/letsencrypt/live/${XUI_DOMAIN}/fullchain.pem" ]]; then
    openssl x509 -in "/etc/letsencrypt/live/${XUI_DOMAIN}/fullchain.pem" -noout -subject -issuer -dates
  else
    echo "certificate: not-found"
  fi
}

ACTION="${1:---status}"
case "$ACTION" in
  -h|--help) usage ;;
  --status) require_root; status ;;
  --install) require_root; install_packages ;;
  --configure) require_root; write_https_config ;;
  --issue) require_root; issue_certificate ;;
  --renew) require_root; if [[ "${2:-}" == "--dry-run" ]]; then certbot renew --dry-run; else certbot renew --deploy-hook "systemctl reload nginx"; fi ;;
  --xui-path) require_root; set_xui_path "${2:-}" ;;
  *) echo "未知动作: $ACTION" >&2; usage; exit 2 ;;
esac
