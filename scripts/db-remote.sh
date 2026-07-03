#!/bin/bash
# 数据库备份/还原的远程编排（在本地开发机运行，通过 SSH 操作服务器）
# - pull:  远程备份 → 本地（可选 --fresh 先在远程触发一次新备份）
# - push:  本地备份 → 远程还原（上传 dump 到远程，调用 restore.sh）
#
# 用法:
#   ./scripts/db-remote.sh pull --env production [--fresh] [--out <dir>]
#   ./scripts/db-remote.sh push --env production --file <pg.dump> [--redis <rdb.gz>] [--yes] [--no-safety-backup]
#   ./scripts/db-remote.sh --help
#
# 需要本地 .env.production / .env.test 配置:
#   DEPLOY_HOST / DEPLOY_SSH_USER / DEPLOY_SSH_PASSWORD
# （与 pnpm deploy / pnpm bootstrap 共用同一套 SSH 凭证）

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
# shellcheck source=scripts/lib/deploy-remote.sh
source "$ROOT/scripts/lib/deploy-remote.sh"

REGORA_OPS_DIR="/etc/regora/scripts"
REMOTE_RESTORE_STAGING="/tmp/regora-restore-staging"

usage() {
  sed -n '3,13p' "$0"
  exit 0
}

remote_backup_dir_for() {
  case "$1" in
    test) echo "/backups/test" ;;
    *)    echo "/var/backups/regora" ;;
  esac
}

validate_env() {
  case "$1" in
    production|test) return 0 ;;
    *) log_die "无效环境: $1（仅支持 production / test）" ;;
  esac
}

# 同步 backup.sh / restore.sh / lib/log.sh 到远程 /etc/regora/scripts/
sync_remote_scripts() {
  log_info "同步脚本到远程 ${REGORA_OPS_DIR} ..."
  _run_ssh "mkdir -p '${REGORA_OPS_DIR}/lib'"
  _run_scp "$ROOT/scripts/backup.sh"  "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REGORA_OPS_DIR}/backup.sh"
  _run_scp "$ROOT/scripts/restore.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REGORA_OPS_DIR}/restore.sh"
  _run_scp "$ROOT/scripts/lib/log.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REGORA_OPS_DIR}/lib/log.sh"
  _run_ssh "chmod +x '${REGORA_OPS_DIR}/backup.sh' '${REGORA_OPS_DIR}/restore.sh'"
}

# 探测远程最新备份文件路径（优先非 safety），无则输出空字符串
detect_remote_latest() {
  local remote_dir="$1" pattern="$2"
  _run_ssh "f=\$(ls -t '${remote_dir}'/${pattern} 2>/dev/null | grep -v safety | head -1); [ -n \"\$f\" ] || f=\$(ls -t '${remote_dir}'/${pattern} 2>/dev/null | head -1); echo \"\$f\""
}

cmd_pull() {
  local env out fresh
  env="production"; out=""; fresh=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)   env="$2"; shift 2 ;;
      --out)   out="$2"; shift 2 ;;
      --fresh) fresh=1; shift ;;
      *) log_die "pull: 未知参数 $1" ;;
    esac
  done
  validate_env "$env"
  load_deploy_credentials "$env"

  local remote_dir
  remote_dir="$(remote_backup_dir_for "$env")"
  [ -n "$out" ] || out="$ROOT/backups/${env}"
  mkdir -p "$out"

  log_info "目标: ${DEPLOY_SSH_USER}@${DEPLOY_HOST} (${env})"
  log_info "远程备份目录: ${remote_dir}"
  log_info "本地保存目录: ${out}"
  sync_remote_scripts

  if [ "$fresh" = "1" ]; then
    log_info "在远程触发新备份..."
    _run_ssh "bash '${REGORA_OPS_DIR}/backup.sh' --env '${env}'"
  fi

  local pg_remote redis_remote pg_local redis_local
  pg_remote="$(detect_remote_latest "$remote_dir" "regora_backup_*.dump")"
  redis_remote="$(detect_remote_latest "$remote_dir" "regora_redis_*.rdb.gz")"

  if [ -z "$pg_remote" ] && [ -z "$redis_remote" ]; then
    log_die "远程未找到任何备份文件 (${remote_dir})"
  fi

  if [ -n "$pg_remote" ]; then
    pg_local="${out}/$(basename "$pg_remote")"
    log_info "下载 PG 备份: ${pg_remote}"
    _run_scp "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${pg_remote}" "$pg_local"
    chmod 600 "$pg_local"
    log_success "PG 备份已保存: $pg_local"
  else
    log_warn "远程无 PG 备份，跳过"
  fi

  if [ -n "$redis_remote" ]; then
    redis_local="${out}/$(basename "$redis_remote")"
    log_info "下载 Redis 备份: ${redis_remote}"
    _run_scp "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${redis_remote}" "$redis_local"
    chmod 600 "$redis_local"
    log_success "Redis 备份已保存: $redis_local"
  else
    log_warn "远程无 Redis 备份，跳过"
  fi

  log_success "拉取完成 → ${out}"
}

cmd_push() {
  local env pg_local redis_local assume_yes no_safety
  env="production"; pg_local=""; redis_local=""; assume_yes=0; no_safety=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)              env="$2"; shift 2 ;;
      --file)             pg_local="$2"; shift 2 ;;
      --redis)            redis_local="$2"; shift 2 ;;
      --yes)              assume_yes=1; shift ;;
      --no-safety-backup) no_safety=1; shift ;;
      *) log_die "push: 未知参数 $1" ;;
    esac
  done
  validate_env "$env"

  [ -n "$pg_local" ] || log_die "push 需要 --file <pg.dump>"
  [ -f "$pg_local" ] || log_die "本地 PG 备份不存在: $pg_local"
  if [ -n "$redis_local" ] && [ ! -f "$redis_local" ]; then
    log_die "本地 Redis 备份不存在: $redis_local"
  fi

  load_deploy_credentials "$env"

  log_info "目标: ${DEPLOY_SSH_USER}@${DEPLOY_HOST} (${env})"
  log_info "PG 备份: ${pg_local}"
  [ -n "$redis_local" ] && log_info "Redis 备份: ${redis_local}"
  log_warn "将清空远程 ${env} 数据库并还原，当前数据会被覆盖（远程会先生成安全备份）"

  # 本地确认（远程 restore.sh 以 --yes 非交互运行，确认必须在本地完成）
  if [ "$assume_yes" != "1" ]; then
    if [ ! -t 0 ]; then
      log_die "非交互终端，需加 --yes 确认远程还原"
    fi
    read -r -p "确认推送到远程 ${env} 还原？输入大写 YES 继续: " reply
    [ "$reply" = "YES" ] || log_die "已取消"
  fi

  sync_remote_scripts

  local pg_name redis_name restore_cmd
  pg_name="$(basename "$pg_local")"

  log_info "上传备份到远程 ${REMOTE_RESTORE_STAGING} ..."
  _run_ssh "rm -rf '${REMOTE_RESTORE_STAGING}' && mkdir -p '${REMOTE_RESTORE_STAGING}'"
  _run_scp "$pg_local" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_RESTORE_STAGING}/${pg_name}"

  # 远程非交互执行：始终带 --yes；--no-safety-backup 按需透传
  restore_cmd="bash '${REGORA_OPS_DIR}/restore.sh' --env '${env}' --file '${REMOTE_RESTORE_STAGING}/${pg_name}' --yes"
  if [ -n "$redis_local" ]; then
    redis_name="$(basename "$redis_local")"
    _run_scp "$redis_local" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_RESTORE_STAGING}/${redis_name}"
    restore_cmd="${restore_cmd} --redis-file '${REMOTE_RESTORE_STAGING}/${redis_name}'"
  fi
  [ "$no_safety" = "1" ] && restore_cmd="${restore_cmd} --no-safety-backup"

  log_info "在远程执行还原（含还原前安全备份）..."
  _run_ssh "$restore_cmd"

  log_info "清理远程暂存目录..."
  _run_ssh "rm -rf '${REMOTE_RESTORE_STAGING}'"

  log_success "远程还原完成 (${env})"
}

main() {
  local subcmd="${1:-}"
  if [ -z "$subcmd" ] || [ "$subcmd" = "--help" ] || [ "$subcmd" = "-h" ]; then
    usage
  fi
  shift
  case "$subcmd" in
    pull) cmd_pull "$@" ;;
    push) cmd_push "$@" ;;
    *)    log_die "未知子命令: $subcmd（可用: pull | push）" ;;
  esac
}

main "$@"
