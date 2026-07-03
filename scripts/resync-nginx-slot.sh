#!/bin/bash
# 将 Nginx 同步到当前活跃蓝绿槽位（修复 Certbot SSL 块端口未更新导致的 HTTPS 502）
# 用法: sudo ./scripts/resync-nginx-slot.sh [--env production|test]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/blue-green.sh
source "${SCRIPT_DIR}/lib/blue-green.sh"

ENVIRONMENT="production"

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --help|-h)
      echo "用法: $0 [--env production|test]"
      exit 0
      ;;
    *)
      echo "未知选项: $1" >&2
      exit 1
      ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  bg_error "请使用 root 运行此脚本"
  exit 1
fi

bg_load_env "$ENVIRONMENT"
ACTIVE_SLOT="$(bg_get_active_slot)"

bg_info "重新同步 Nginx -> 活跃槽位 ${ACTIVE_SLOT}"
bg_switch_nginx_slot "$ACTIVE_SLOT"

bg_info "完成。验证: curl -fsS https://\$(grep -m1 server_name /etc/nginx/sites-enabled/* | awk '{print \$2}' | tr -d ';')/health"
