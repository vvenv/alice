#!/bin/bash

# 管理 alice 备份定时任务
# 用法:
#   ./scripts/backup-cron.sh install --env production|test
#   ./scripts/backup-cron.sh disable --env production|test
#   ./scripts/backup-cron.sh status

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

CRON_TAG_PREFIX="alice-backup"
REGORA_OPS_DIR="/etc/alice/scripts"
ACTION=""
ENVIRONMENT="production"


usage() {
    sed -n '3,7p' "$0"
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            install|disable|status)
                ACTION="$1"
                shift
                ;;
            --env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                log_error "未知参数: $1"
                usage
                ;;
        esac
    done

    if [ -z "$ACTION" ]; then
        log_error "请指定操作: install | disable | status"
        usage
    fi

    if [ "$ENVIRONMENT" != "production" ] && [ "$ENVIRONMENT" != "test" ]; then
        log_error "无效的环境参数: ${ENVIRONMENT}（仅支持 production 或 test）"
        exit 1
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

set_env_vars() {
    if [ "$ENVIRONMENT" = "test" ]; then
        BACKUP_DIR="/backups/test"
        LOCK_FILE="/tmp/regora_backup_test.lock"
    else
        BACKUP_DIR="/var/backups/alice"
        LOCK_FILE="/tmp/regora_backup.lock"
    fi

    CRON_TAG="# ${CRON_TAG_PREFIX}-${ENVIRONMENT}"
    LOG_FILE="/var/log/alice-backup-${ENVIRONMENT}.log"
    BACKUP_SCRIPT="${REGORA_OPS_DIR}/backup.sh"
}

resolve_source_backup_script() {
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    echo "${script_dir}/backup.sh"
}

sync_backup_script() {
    local source source_lib_dir
    source="$(resolve_source_backup_script)"
    source_lib_dir="$(dirname "$source")/lib"

    if [ ! -f "$source" ]; then
        if [ -f "$BACKUP_SCRIPT" ]; then
            log_warn "未找到 ${source}，保留现有 ${BACKUP_SCRIPT}"
            return 0
        fi
        log_error "备份脚本不存在: $source"
        exit 1
    fi

    mkdir -p "$REGORA_OPS_DIR/lib"
    install -m 755 "$source" "$BACKUP_SCRIPT"
    if [ -f "${source_lib_dir}/log.sh" ]; then
        install -m 755 "${source_lib_dir}/log.sh" "${REGORA_OPS_DIR}/lib/log.sh"
    fi
    log_info "已同步备份脚本 -> ${BACKUP_SCRIPT}"
}

ensure_cron_service() {
    if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
        return 0
    fi

    log_warn "cron 服务未运行，尝试启动..."
    systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || {
        log_error "无法启动 cron 服务，请手动检查: systemctl status cron"
        exit 1
    }
    systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
}

remove_cron_for_env() {
    set_env_vars

    local current filtered
    current=$(crontab -l 2>/dev/null || true)
    if [ -z "$current" ]; then
        return 0
    fi

    filtered=$(printf '%s\n' "$current" | grep -vF "$CRON_TAG" || true)
    filtered=$(printf '%s\n' "$filtered" | grep -vF "$BACKUP_SCRIPT" || true)
    filtered=$(printf '%s\n' "$filtered" | grep -vF "/var/www/alice/scripts/backup.sh" || true)
    filtered=$(printf '%s\n' "$filtered" | grep -vF "/var/www/regora_test/scripts/backup.sh" || true)

    if [ -n "$filtered" ]; then
        printf '%s\n' "$filtered" | crontab -
    else
        crontab -r 2>/dev/null || true
    fi
}

install_cron() {
    set_env_vars
    sync_backup_script

    if [ ! -f "$BACKUP_SCRIPT" ]; then
        log_error "备份脚本不存在: $BACKUP_SCRIPT"
        exit 1
    fi

    ensure_cron_service
    mkdir -p "$BACKUP_DIR"
    touch "$LOG_FILE"

    remove_cron_for_env

    (crontab -l 2>/dev/null; echo "0 8 * * * flock -n ${LOCK_FILE} bash ${BACKUP_SCRIPT} --env ${ENVIRONMENT} >> ${LOG_FILE} 2>&1 ${CRON_TAG}") | crontab -
    (crontab -l 2>/dev/null; echo "0 9 * * 0 find ${BACKUP_DIR} -name \"regora_backup_*.dump\" -mtime +30 -delete ${CRON_TAG}") | crontab -
    (crontab -l 2>/dev/null; echo "0 9 * * 0 find ${BACKUP_DIR} -name \"regora_redis_*.rdb.gz\" -mtime +30 -delete ${CRON_TAG}") | crontab -

    log_info "已安装 $ENVIRONMENT 环境备份定时任务"
    log_info "备份脚本: $BACKUP_SCRIPT"
    log_info "备份日志: $LOG_FILE"
    log_info "手动测试: bash $BACKUP_SCRIPT --env $ENVIRONMENT"
}

disable_cron() {
    remove_cron_for_env
    log_info "已禁用 $ENVIRONMENT 环境备份定时任务"
}

show_status() {
    local current matches
    current=$(crontab -l 2>/dev/null || true)

    if [ -z "$current" ]; then
        log_warn "当前用户没有 crontab 条目"
        exit 0
    fi

    matches=$(printf '%s\n' "$current" | grep -F "$CRON_TAG_PREFIX" || true)
    if [ -z "$matches" ]; then
        log_warn "未找到 alice 备份定时任务"
        exit 0
    fi

    log_info "当前 alice 备份定时任务:"
    printf '%s\n' "$matches"
}

main() {
    parse_args "$@"

    if [ "$ACTION" != "status" ]; then
        check_root
    fi

    case "$ACTION" in
        install) install_cron ;;
        disable) disable_cron ;;
        status)  show_status ;;
    esac
}

main "$@"
