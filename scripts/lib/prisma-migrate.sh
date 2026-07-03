#!/bin/bash
# Shared Prisma migrate helpers for deploy scripts

prisma_db_url_for_psql() {
  local url="${1:-${DATABASE_URL:-}}"
  echo "$url" | sed 's#[?].*##'
}

# Return squashed init migration name when repo has exactly one *_init directory.
prisma_find_squashed_init_migration() {
  local app_dir="${1:-.}"
  local migrations_dir="$app_dir/packages/server/prisma/migrations"
  local dir name count=0 init_name=""

  if [ ! -d "$migrations_dir" ]; then
    return 0
  fi

  for dir in "$migrations_dir"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    count=$((count + 1))
    case "$name" in
      *_init) init_name="$name" ;;
    esac
  done

  if [ "$count" -eq 1 ] && [ -n "$init_name" ]; then
    echo "$init_name"
  fi
}

# Baseline squashed init on existing DBs: schema already present, migration history stale.
prisma_reconcile_squashed_init() {
  local app_dir="${1:-.}"
  local init_name db_url init_applied table_count migration_count

  if [ -z "${DATABASE_URL:-}" ] || ! command -v psql &>/dev/null; then
    return 0
  fi

  init_name="$(prisma_find_squashed_init_migration "$app_dir")"
  [ -n "$init_name" ] || return 0

  db_url="$(prisma_db_url_for_psql)"

  init_applied="$(
    psql "$db_url" -tAc \
      "SELECT COUNT(*) FROM \"_prisma_migrations\" WHERE migration_name = '${init_name}' AND finished_at IS NOT NULL;" \
      2>/dev/null || echo "0"
  )"
  init_applied="$(echo "$init_applied" | xargs)"
  [ "${init_applied:-0}" -gt 0 ] && return 0

  table_count="$(
    psql "$db_url" -tAc \
      "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> '_prisma_migrations';" \
      2>/dev/null || echo "0"
  )"
  table_count="$(echo "$table_count" | xargs)"
  [ "${table_count:-0}" -eq 0 ] && return 0

  migration_count="$(
    psql "$db_url" -tAc 'SELECT COUNT(*) FROM "_prisma_migrations";' 2>/dev/null || echo "0"
  )"
  migration_count="$(echo "$migration_count" | xargs)"

  echo "[INFO] 检测到 migration 历史收敛，对已有库自动 baseline: ${init_name}（旧记录 ${migration_count} 条）"
  psql "$db_url" -c 'DELETE FROM "_prisma_migrations";'
  (cd "$app_dir" && pnpm --filter server exec prisma migrate resolve --applied "$init_name")
}

# Recover failed migrations, reconcile squashed init, then deploy.
prisma_migrate_deploy() {
  local app_dir="${1:-.}"

  prisma_recover_failed_migrations "$app_dir"
  prisma_reconcile_squashed_init "$app_dir"
  (cd "$app_dir" && pnpm --filter server exec prisma migrate deploy)
}

# Mark failed migrations as rolled-back so migrate deploy can retry.
# Safe when the failed migration ran inside a transaction (PostgreSQL rolls back DDL).
prisma_recover_failed_migrations() {
  local app_dir="${1:-.}"

  if [ -z "${DATABASE_URL:-}" ]; then
    return 0
  fi

  if ! command -v psql &>/dev/null; then
    return 0
  fi

  local db_url failed migration
  db_url="$(prisma_db_url_for_psql)"

  failed="$(
    psql "$db_url" -tAc \
      "SELECT migration_name FROM \"_prisma_migrations\" WHERE finished_at IS NULL AND rolled_back_at IS NULL AND started_at IS NOT NULL;" \
      2>/dev/null || true
  )"

  if [ -z "$failed" ]; then
    return 0
  fi

  while IFS= read -r migration; do
    migration="$(echo "$migration" | xargs)"
    [ -z "$migration" ] && continue
    echo "[WARN] 发现失败的 migration: ${migration}，标记为 rolled-back 后重试 deploy..."
    (cd "$app_dir" && pnpm --filter server exec prisma migrate resolve --rolled-back "$migration")
  done <<< "$failed"
}
