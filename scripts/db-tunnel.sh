#!/bin/bash
# 本地 SSH 隧道 → 生产/测试机 localhost Postgres（及可选 Redis）
#
# 用法:
#   ./scripts/db-tunnel.sh start  [--env production] [--pg-port 15432] [--redis-port 16379] [--no-redis]
#   ./scripts/db-tunnel.sh ensure [--env production] [--pg-port 15432] [--retry 5] [--interval 2]
#   ./scripts/db-tunnel.sh watch  [--env production] [--pg-port 15432] [--interval 10]
#   ./scripts/db-tunnel.sh stop   [--pg-port 15432] [--redis-port 16379]
#   ./scripts/db-tunnel.sh status [--pg-port 15432]
#
# 凭证: .env.production / .env.test 中的 DEPLOY_HOST / DEPLOY_SSH_USER / DEPLOY_SSH_PASSWORD
# 环境变量: 复制 .env.local 为 .env.tunnel，改 DATABASE_URL / REDIS_PORT（见 scripts/db-tunnel.sh 输出）

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
# shellcheck source=scripts/lib/deploy-remote.sh
source "$ROOT/scripts/lib/deploy-remote.sh"

DEFAULT_PG_PORT=15432
DEFAULT_REDIS_PORT=16379
PID_DIR="${TMPDIR:-/tmp}/alice-tunnel"

usage() {
  sed -n '3,14p' "$0"
  exit 0
}

pid_file_for() {
  echo "${PID_DIR}/pg-${1}.pid"
}

tunnel_pids() {
  local pg_port="$1"
  local pid_file
  pid_file="$(pid_file_for "$pg_port")"
  if [ -f "$pid_file" ]; then
    cat "$pid_file"
  fi
}

tunnel_running() {
  local pg_port="$1"
  local pid
  pid="$(tunnel_pids "$pg_port")"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

port_listening() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  nc -z 127.0.0.1 "$port" >/dev/null 2>&1
}

_tunnel_healthy() {
  port_listening "$1"
}

_sync_pid_file() {
  local pg_port="$1"
  local pid
  pid="$(_find_tunnel_pid "$pg_port")"
  if [ -n "$pid" ]; then
    echo "$pid" > "$(pid_file_for "$pg_port")"
  fi
}

_clear_stale_pid() {
  rm -f "$(pid_file_for "$1")"
}

_start_ssh_background() {
  local pg_port="$1" redis_port="$2" with_redis="$3"
  local stderr_file rc
  stderr_file="$(mktemp)"
  local -a forwards=(-L "${pg_port}:127.0.0.1:5432")
  if [ "$with_redis" = "1" ]; then
    forwards+=(-L "${redis_port}:127.0.0.1:6379")
  fi

  if ssh "${_ssh_common_opts[@]}" -o BatchMode=yes -f -N "${forwards[@]}" \
    "${DEPLOY_SSH_USER}@${DEPLOY_HOST}" 2>"$stderr_file"; then
    rm -f "$stderr_file"
    return 0
  fi
  rc=$?

  if [ -n "${DEPLOY_SSH_PASSWORD:-}" ]; then
    _require_sshpass
    if SSHPASS="$DEPLOY_SSH_PASSWORD" sshpass -e ssh \
      "${_ssh_common_opts[@]}" \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      -f -N "${forwards[@]}" \
      "${DEPLOY_SSH_USER}@${DEPLOY_HOST}" 2>"$stderr_file"; then
      rm -f "$stderr_file"
      return 0
    fi
  fi

  if [ "$rc" -eq 255 ] || _ssh_auth_failure_in_stderr "$stderr_file"; then
    rm -f "$stderr_file"
    _ssh_auth_failure_hint
  fi
  cat "$stderr_file" >&2
  rm -f "$stderr_file"
  return "$rc"
}

_find_tunnel_pid() {
  local pg_port="$1"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "ssh.*${pg_port}:127\\.0\\.0\\.1:5432" 2>/dev/null | head -1 || true
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$pg_port" -sTCP:LISTEN -t 2>/dev/null | head -1 || true
  fi
}

_start_tunnel() {
  local pg_port="$1" redis_port="$2" with_redis="$3"

  if _tunnel_healthy "$pg_port"; then
    _sync_pid_file "$pg_port"
    return 0
  fi

  log_info "建立 SSH 隧道 ${DEPLOY_SSH_USER}@${DEPLOY_HOST}"
  log_info "  本地 ${pg_port} → 远程 127.0.0.1:5432"
  if [ "$with_redis" = "1" ]; then
    log_info "  本地 ${redis_port} → 远程 127.0.0.1:6379"
  fi

  if ! _start_ssh_background "$pg_port" "$redis_port" "$with_redis"; then
    return 1
  fi

  sleep 0.5
  local pid
  pid="$(_find_tunnel_pid "$pg_port")"
  if [ -z "$pid" ]; then
    log_error "隧道启动失败（未检测到监听端口 ${pg_port}）"
    return 1
  fi
  echo "$pid" > "$(pid_file_for "$pg_port")"
  log_success "隧道已启动 (pid ${pid})"
  return 0
}

_parse_tunnel_args() {
  TUNNEL_ENV="production"
  TUNNEL_PG_PORT="$DEFAULT_PG_PORT"
  TUNNEL_REDIS_PORT="$DEFAULT_REDIS_PORT"
  TUNNEL_WITH_REDIS=1
  TUNNEL_RETRIES=5
  TUNNEL_INTERVAL=2
  TUNNEL_WATCH_INTERVAL=10

  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)        TUNNEL_ENV="$2"; shift 2 ;;
      --pg-port)    TUNNEL_PG_PORT="$2"; shift 2 ;;
      --redis-port) TUNNEL_REDIS_PORT="$2"; shift 2 ;;
      --no-redis)   TUNNEL_WITH_REDIS=0; shift ;;
      --retry)      TUNNEL_RETRIES="$2"; shift 2 ;;
      --interval)   TUNNEL_INTERVAL="$2"; shift 2 ;;
      *)            log_die "未知参数 $1" ;;
    esac
  done
}

cmd_start() {
  _parse_tunnel_args "$@"
  load_deploy_credentials "$TUNNEL_ENV"
  mkdir -p "$PID_DIR"

  if _tunnel_healthy "$TUNNEL_PG_PORT"; then
    _sync_pid_file "$TUNNEL_PG_PORT"
    log_warn "端口 ${TUNNEL_PG_PORT} 已有隧道在运行"
    cmd_status --pg-port "$TUNNEL_PG_PORT"
    return 0
  fi

  _clear_stale_pid "$TUNNEL_PG_PORT"
  _start_tunnel "$TUNNEL_PG_PORT" "$TUNNEL_REDIS_PORT" "$TUNNEL_WITH_REDIS"

  log_info "使用 .env.tunnel：DATABASE_URL=postgresql://alice:alice@localhost:${TUNNEL_PG_PORT}/alice"
  if [ "$TUNNEL_WITH_REDIS" = "1" ]; then
    log_info "REDIS_HOST=localhost REDIS_PORT=${TUNNEL_REDIS_PORT}"
  fi
  log_info "启动开发: pnpm dev:tunnel"
}

cmd_ensure() {
  _parse_tunnel_args "$@"
  load_deploy_credentials "$TUNNEL_ENV"
  mkdir -p "$PID_DIR"

  if _tunnel_healthy "$TUNNEL_PG_PORT"; then
    _sync_pid_file "$TUNNEL_PG_PORT"
    log_success "隧道就绪 (localhost:${TUNNEL_PG_PORT})"
    return 0
  fi

  _clear_stale_pid "$TUNNEL_PG_PORT"

  local attempt=1
  while [ "$attempt" -le "$TUNNEL_RETRIES" ]; do
    if [ "$TUNNEL_RETRIES" -gt 1 ]; then
      log_info "建立隧道 (尝试 ${attempt}/${TUNNEL_RETRIES})..."
    fi
    if _start_tunnel "$TUNNEL_PG_PORT" "$TUNNEL_REDIS_PORT" "$TUNNEL_WITH_REDIS"; then
      log_success "隧道就绪 (localhost:${TUNNEL_PG_PORT})"
      return 0
    fi
    if [ "$attempt" -lt "$TUNNEL_RETRIES" ]; then
      sleep "$TUNNEL_INTERVAL"
    fi
    attempt=$((attempt + 1))
  done

  log_die "隧道在 ${TUNNEL_RETRIES} 次尝试后仍不可用"
}

cmd_watch() {
  local env pg_port redis_port with_redis interval
  env="production"
  pg_port="$DEFAULT_PG_PORT"
  redis_port="$DEFAULT_REDIS_PORT"
  with_redis=1
  interval=10
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)        env="$2"; shift 2 ;;
      --pg-port)    pg_port="$2"; shift 2 ;;
      --redis-port) redis_port="$2"; shift 2 ;;
      --no-redis)   with_redis=0; shift ;;
      --interval)   interval="$2"; shift 2 ;;
      *)            log_die "watch: 未知参数 $1" ;;
    esac
  done

  load_deploy_credentials "$env"
  mkdir -p "$PID_DIR"

  log_info "隧道看门狗已启动 (每 ${interval}s 检查 localhost:${pg_port})"

  while true; do
    sleep "$interval"
    if _tunnel_healthy "$pg_port"; then
      continue
    fi
    log_warn "隧道断开，正在重连 localhost:${pg_port}..."
    _clear_stale_pid "$pg_port"
    if _start_tunnel "$pg_port" "$redis_port" "$with_redis"; then
      log_success "隧道已恢复"
    else
      log_error "隧道重连失败，${interval}s 后重试"
    fi
  done
}

cmd_stop() {
  local pg_port="$DEFAULT_PG_PORT"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --pg-port) pg_port="$2"; shift 2 ;;
      *) log_die "stop: 未知参数 $1" ;;
    esac
  done

  local pid pid_file
  pid_file="$(pid_file_for "$pg_port")"
  pid="$(tunnel_pids "$pg_port")"
  if [ -z "$pid" ]; then
    pid="$(_find_tunnel_pid "$pg_port")"
  fi
  if [ -z "$pid" ]; then
    log_warn "未找到端口 ${pg_port} 的隧道"
    rm -f "$pid_file"
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  rm -f "$pid_file"
  log_success "隧道已停止 (pid ${pid})"
}

cmd_status() {
  local pg_port="$DEFAULT_PG_PORT"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --pg-port) pg_port="$2"; shift 2 ;;
      *) log_die "status: 未知参数 $1" ;;
    esac
  done

  local pid
  pid="$(tunnel_pids "$pg_port")"
  [ -z "$pid" ] && pid="$(_find_tunnel_pid "$pg_port")"
  if _tunnel_healthy "$pg_port"; then
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      log_success "隧道运行中: localhost:${pg_port} → 生产 Postgres (pid ${pid})"
    else
      log_success "隧道运行中: localhost:${pg_port} → 生产 Postgres"
    fi
    return 0
  fi
  log_warn "隧道未运行 (端口 ${pg_port})"
  return 1
}

main() {
  local subcmd="${1:-}"
  if [ -z "$subcmd" ] || [ "$subcmd" = "--help" ] || [ "$subcmd" = "-h" ]; then
    usage
  fi
  shift
  case "$subcmd" in
    start)  cmd_start "$@" ;;
    ensure) cmd_ensure "$@" ;;
    watch)  cmd_watch "$@" ;;
    stop)   cmd_stop "$@" ;;
    status) cmd_status "$@" ;;
    *)      log_die "未知子命令: $subcmd（可用: start | ensure | watch | stop | status）" ;;
  esac
}

main "$@"
