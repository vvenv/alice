#!/bin/bash

# 数据库初始化脚本
# 用法: ./scripts/seed.sh --env test

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"


# 解析命令行参数
parse_args() {
    ENVIRONMENT="production"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # 如果没有指定环境，根据当前目录自动检测
    if [ "$ENVIRONMENT" = "production" ]; then
        CURRENT_DIR=$(pwd)
        if [[ "$CURRENT_DIR" == "/var/www/regora_test" ]]; then
            ENVIRONMENT="test"
        fi
    fi

    # 验证环境参数
    if [ "$ENVIRONMENT" != "production" ] && [ "$ENVIRONMENT" != "test" ]; then
        log_error "无效的环境参数: $ENVIRONMENT (仅支持 production 或 test)"
        exit 1
    fi

    log_info "初始化环境: $ENVIRONMENT"
}

# 加载 DATABASE_URL（本地 .env.local；服务器 .env / .env.production / .env.test）
load_env() {
    local script_dir repo_root env_file
    script_dir=$(cd "$(dirname "$0")" && pwd)
    repo_root="$script_dir/.."

    if [ -f "$repo_root/.env.local" ]; then
        env_file="$repo_root/.env.local"
    elif [ "$ENVIRONMENT" = "test" ] && [ -f "$repo_root/.env.test" ]; then
        env_file="$repo_root/.env.test"
    elif [ -f "$repo_root/.env.production" ]; then
        env_file="$repo_root/.env.production"
    elif [ -f "$repo_root/.env" ]; then
        env_file="$repo_root/.env"
    else
        env_file=""
    fi

    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        # 仅导出 DATABASE_URL，避免污染环境
        DATABASE_URL=$(grep -E "^DATABASE_URL=" "$env_file" | head -1 | cut -d= -f2-)
        # 去除 Prisma 特有的 schema 查询参数（psql 不识别）
        DATABASE_URL=$(echo "$DATABASE_URL" | sed -E 's/[?&]schema=[^&]*//')
        export DATABASE_URL
    fi
}

# psql 包装器：优先使用 DATABASE_URL，否则回退到生产环境的 sudo -u postgres
psql_exec() {
    if [ -n "$DATABASE_URL" ]; then
        psql "$DATABASE_URL" "$@"
    else
        # 生产环境（Linux）：需要 root 权限通过 postgres 用户连接
        if [ "$EUID" -ne 0 ]; then
            log_error "未检测到 DATABASE_URL，需要使用 root 用户运行此脚本"
            exit 1
        fi
        # 根据环境确定数据库名称
        if [ "$ENVIRONMENT" = "test" ]; then
            DB_NAME="regora_test"
        else
            DB_NAME="alice"
        fi
        sudo -u postgres psql -d $DB_NAME "$@"
    fi
}

# 生成 bcrypt 哈希（使用 node）
# 必须在 packages/server 目录运行，因为 bcrypt 安装在该 workspace 包中（pnpm 不做 hoist）
# 通过环境变量传递密码，避免特殊字符引发的注入或解析错误
generate_hash() {
    local password=$1
    local script_dir
    script_dir=$(cd "$(dirname "$0")" && pwd)
    (cd "$script_dir/../packages/server" && SEED_RAW_PASSWORD="$password" node -e "
const bcrypt = require('bcrypt');
console.log(bcrypt.hashSync(process.env.SEED_RAW_PASSWORD, 10));
")
}

# 数据库初始化
seed_database() {
    log_info "开始数据初始化..."

    # 从环境变量读取或使用默认值
    SEED_USERNAME=${SEED_USERNAME:-admin}
    SEED_PASSWORD=${SEED_PASSWORD:-admin123}

    # 检查是否已存在 superuser
    EXISTING_SUPERUSER=$(psql_exec -tAc "SELECT id FROM \"User\" WHERE role='SUPERUSER' LIMIT 1;")

    if [ -n "$EXISTING_SUPERUSER" ]; then
        log_info "Superuser 已存在，跳过初始化"
        return
    fi

    # 生成密码哈希
    log_info "创建默认 superuser..."
    HASHED_PASSWORD=$(generate_hash "$SEED_PASSWORD")

    # 插入用户
    psql_exec -c "
INSERT INTO \"User\" (id, username, password, role, enabled, created_at, updated_at)
VALUES (
    gen_random_uuid(),
    '$SEED_USERNAME',
    '$HASHED_PASSWORD',
    'SUPERUSER',
    true,
    NOW(),
    NOW()
);
"

    log_info "Superuser 创建成功: $SEED_USERNAME"
    log_info "默认密码: $SEED_PASSWORD"
    log_warn "请在首次登录后立即修改密码！"
}

# 主函数
main() {
    parse_args "$@"
    log_info "开始数据库初始化..."

    load_env
    seed_database

    log_info "数据初始化完成！"
}

main "$@"
