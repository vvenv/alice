#!/bin/bash
# 预检（doctor）：检查本地工具链与部署配置是否就绪，部署 / 发布前自检。
#
# 用法:
#   ./scripts/doctor.sh
#
# 分级:
#   PASS  就绪
#   WARN  非阻塞，按需处理（如可选工具缺失、env 仍为占位值）
#   FAIL  阻塞，必须修复后才能 release / deploy
#
# 退出码: 0 = 无 FAIL（含 WARN）；1 = 存在 FAIL

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/deploy-env.sh
source "$ROOT/scripts/lib/deploy-env.sh"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

_section() {
  printf '\n%s── %s ──%s\n' "${_LOG_DIM:-}" "$1" "${_LOG_RESET:-}"
}

_pass() {
  printf '%s✓ PASS%s  %s%s\n' "${_LOG_OK:-}" "${_LOG_RESET:-}" "$1" "${2:+  ${_LOG_DIM:-}$2${_LOG_RESET:-}}"
  PASS_COUNT=$((PASS_COUNT + 1))
}

_warn() {
  printf '%s⚠ WARN%s  %s%s\n' "${_LOG_WARN:-}" "${_LOG_RESET:-}" "$1" "${2:+  ${_LOG_DIM:-}$2${_LOG_RESET:-}}" >&2
  WARN_COUNT=$((WARN_COUNT + 1))
}

_fail() {
  printf '%s✗ FAIL%s  %s%s\n' "${_LOG_ERR:-}" "${_LOG_RESET:-}" "$1" "${2:+  ${_LOG_DIM:-}$2${_LOG_RESET:-}}" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

_is_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

_check_tool() {
  local tool="$1" hint="$2" level="${3:-warn}"
  if command -v "$tool" >/dev/null 2>&1; then
    _pass "$tool" "已安装"
  else
    if [ "$level" = "fail" ]; then
      _fail "$tool" "未安装 — ${hint}"
    else
      _warn "$tool" "未安装 — ${hint}"
    fi
  fi
}

_scan_main_env() {
  local file="$1" env="$2"
  local path="$ROOT/$file"
  if [ ! -f "$path" ]; then
    _warn "$file" "未创建（部署 ${env} 前需复制对应 .example 并填入凭证）"
    return
  fi
  _pass "$file" "已创建"

  # 加载到当前进程仅做读取检查（短生命周期脚本，env 污染可接受）
  unset DB_PASSWORD JWT_SECRET
  load_deploy_env "$ROOT" "$env"

  if deploy_env_is_placeholder_db_password "${DB_PASSWORD:-}"; then
    _warn "${file} DB_PASSWORD" "仍为占位值，请填入真实密码"
  fi
  if deploy_env_is_placeholder_jwt_secret "${JWT_SECRET:-}"; then
    _warn "${file} JWT_SECRET" "仍为占位值，请填入 64 字符随机串"
  fi
}

_scan_edge_env() {
  local file="$1"
  local path="$ROOT/$file"
  if [ ! -f "$path" ]; then
    _warn "$file" "未创建（部署 edge 前需复制 packages/server/scripts/harvest-edge.env.example 并填入主库 DATABASE_URL）"
    return
  fi
  _pass "$file" "已创建"

  unset HARVEST_EXECUTION_REGION DATABASE_URL ATTACHMENT_BASE_DIR
  load_deploy_env "$ROOT" edge

  if [ "${HARVEST_EXECUTION_REGION:-}" != "BR" ]; then
    _warn "${file} HARVEST_EXECUTION_REGION" "需为 BR（当前: ${HARVEST_EXECUTION_REGION:-未设置}）"
  fi
  if [ -z "${DATABASE_URL:-}" ]; then
    _warn "${file} DATABASE_URL" "未设置（Edge 采集需要主库连接）"
  fi
}

# ── 核心工具链（FAIL） ─────────────────────────────────────────

_section "核心工具链"

if command -v node >/dev/null 2>&1; then
  node_ver="$(node -v 2>/dev/null | sed 's/^v//' || true)"
  node_major="${node_ver%%.*}"
  if _is_int "$node_major" && [ "$node_major" -ge 22 ]; then
    _pass "node" "v${node_ver} ($(command -v node))"
  else
    _fail "node" "版本过低 v${node_ver:-未知}，需要 Node.js ≥ 22"
  fi
else
  _fail "node" "未安装（需要 Node.js ≥ 22）"
fi

if command -v pnpm >/dev/null 2>&1; then
  pnpm_ver="$(pnpm --version 2>/dev/null || true)"
  pnpm_major="${pnpm_ver%%.*}"
  if _is_int "$pnpm_major" && [ "$pnpm_major" -ge 11 ]; then
    _pass "pnpm" "v${pnpm_ver} ($(command -v pnpm))"
  else
    _fail "pnpm" "版本过低 v${pnpm_ver:-未知}，需要 pnpm ≥ 11（packageManager 指定 11.9.0）"
  fi
else
  _fail "pnpm" "未安装（需要 pnpm ≥ 11，参考 package.json 的 packageManager 字段）"
fi

_check_tool git "版本控制（release / 部署链路必需）" fail

# ── 部署工具（WARN） ───────────────────────────────────────────

_section "部署工具（缺失为 WARN，按需安装）"

_check_tool docker "Docker（非 Linux 环境 release 构建需要；仅 deploy 可跳过）"
_check_tool sshpass "sshpass（SSH 密码认证需要；使用 SSH 密钥可跳过）"
_check_tool gh "gh CLI（GitHub Release / 与 CI 对齐；仅本地直推可跳过）"

# ── 服务器运行时工具（WARN，本地非必需） ─────────────────────

_section "服务器运行时工具（本地非必需，部署目标服务器需要）"

_check_tool pm2 "PM2 进程管理（部署目标服务器需要）"
_check_tool psql "psql（本地 DB 操作 / 备份验证）"
_check_tool redis-cli "redis-cli（Redis 备份验证）"

# ── env 模板（FAIL — 应随仓库提交） ───────────────────────────

_section "env 模板（随仓库提交）"

for tmpl in scripts/env.production.example scripts/env.test.example packages/server/scripts/harvest-edge.env.example; do
  if [ -f "$ROOT/$tmpl" ]; then
    _pass "$tmpl" "存在"
  else
    _fail "$tmpl" "缺失（仓库应包含此模板）"
  fi
done

# ── 已配置 env 文件（WARN） ───────────────────────────────────

_section "已配置 env 文件（部署前应补全）"

_scan_main_env ".env.production" production
_scan_main_env ".env.test" test
_scan_edge_env ".env.edge"

# ── 工作区状态（WARN） ───────────────────────────────────────

_section "工作区状态"

if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
  _warn "工作区" "有未提交改动（release 前需提交或暂存）"
else
  _pass "工作区" "干净"
fi

# ── 汇总 ─────────────────────────────────────────────────────

printf '\n%s──────────────────────────────────%s\n' "${_LOG_DIM:-}" "${_LOG_RESET:-}"
printf '预检结果: %s%d PASS%s · %s%d WARN%s · %s%d FAIL%s\n' \
  "${_LOG_OK:-}" "$PASS_COUNT" "${_LOG_RESET:-}" \
  "${_LOG_WARN:-}" "$WARN_COUNT" "${_LOG_RESET:-}" \
  "${_LOG_ERR:-}" "$FAIL_COUNT" "${_LOG_RESET:-}"

if [ "$FAIL_COUNT" -gt 0 ]; then
  log_die "存在 ${FAIL_COUNT} 个 FAIL 项，请修复后重试"
elif [ "$WARN_COUNT" -gt 0 ]; then
  log_success "预检通过（${WARN_COUNT} 个 WARN 可按需处理）"
else
  log_success "预检全部通过"
fi
