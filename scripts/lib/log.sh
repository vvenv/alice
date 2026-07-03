#!/bin/bash
# 共享日志库：统一 info / success / warn / error / debug 输出，TTY 感知着色。
#
# 用法:
#   source scripts/lib/log.sh
#   log_info "开始部署"            # ℹ release  开始部署
#   log_success "完成"             # ✓ release  完成
#   log_warn "工作区不干净"        # ⚠ release  工作区不干净   (stderr)
#   log_error "标签已存在"         # ✗ release  标签已存在       (stderr，不退出)
#   log_die "致命错误"             # ✗ release  致命错误         (stderr，exit 1)
#   LOG_DEBUG=1 log_debug "细节"   # ▸ release  细节            (stderr)
#
# tag 自动取 $0 的 basename（去掉 .sh）；可用 LOG_TAG=xxx 覆盖。
# 非终端输出（管道 / 重定向 / cron / CI 日志）自动去色，避免转义码泄漏。
# log_info / log_success → stdout；log_warn / log_error / log_die / log_debug → stderr。
#
# 各脚本可定义本地 wrapper 以保留既有调用点与退出语义，例如:
#   info()  { log_info "$@"; }      # 非退出
#   error() { log_die  "$@"; }      # 退出

# 直接执行时打印用法；被 source 时不触发。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "用法: source $(basename "$0")"
  echo "  提供 log_info / log_success / log_warn / log_error / log_die / log_debug 函数"
  exit 0
fi

: "${LOG_TAG:=$(basename "$0" .sh)}"

# TTY 感知：仅 stderr 连接终端时着色（cron / CI 日志 / 管道自动去色）
if [ -t 2 ]; then
  _LOG_RESET=$'\033[0m'
  _LOG_DIM=$'\033[2m'
  _LOG_INFO=$'\033[36m'   # cyan
  _LOG_OK=$'\033[32m'     # green
  _LOG_WARN=$'\033[33m'   # yellow
  _LOG_ERR=$'\033[31m'    # red
else
  _LOG_RESET='' _LOG_DIM='' _LOG_INFO='' _LOG_OK='' _LOG_WARN='' _LOG_ERR=''
fi

# 内部：_log_emit <icon> <color> <stream:1|2> <msg>
_log_emit() {
  printf '%s%s%s %s%s%s  %s\n' \
    "$2" "$1" "$_LOG_RESET" \
    "$_LOG_DIM" "$LOG_TAG" "$_LOG_RESET" \
    "$4" >&"$3"
}

log_info()    { _log_emit 'ℹ' "$_LOG_INFO" 1 "$*"; }
log_success() { _log_emit '✓' "$_LOG_OK"   1 "$*"; }
log_warn()    { _log_emit '⚠' "$_LOG_WARN" 2 "$*"; }
log_error()   { _log_emit '✗' "$_LOG_ERR"  2 "$*"; }
log_die()     { _log_emit '✗' "$_LOG_ERR"  2 "$*"; exit "${LOG_EXIT_CODE:-1}"; }
log_debug()   { [ "${LOG_DEBUG:-0}" = 1 ] && _log_emit '▸' "$_LOG_DIM" 2 "$*" || true; }
