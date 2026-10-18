#!/usr/bin/env bash
# Alice 开发入口。无参数进入交互菜单；把常用 flutter / pnpm / 发版命令收成一处。
#
# 用法:
#   ./do.sh                         # 交互主菜单
#   ./do.sh run                     # flutter run（连着的设备）
#   ./do.sh run --chrome            # Web（Chrome）
#   ./do.sh run -d <id>             # 指定设备
#   ./do.sh test                    # flutter analyze + flutter test
#   ./do.sh test --lint             # 再加上 pnpm lint
#   ./do.sh install                 # 打 debug APK → adb 安装并打开
#   ./do.sh install --release       # release APK（需 ZHIPU_API_KEY）
#   ./do.sh install --no-launch     # 装完不打开
#   ./do.sh install -s <serial>     # 指定 adb 设备
#   ./do.sh release                 # Android 发版（交互选版本；默认 patch）
#   ./do.sh release patch           # 升 patch 后发版
#   ./do.sh release minor|major     # 升次/主版本后发版
#   ./do.sh release keep            # 保持当前版本发版
#   ./do.sh release 0.8.0           # 指定版本发版
#   ./do.sh website                 # 落地页 + /app/
#   ./do.sh website --skip-webapp   # 仅落地页
#   ./do.sh webapp                  # 仅更新 /app/
#   ./do.sh screenshots             # 上传 docs/screenshots/ 到 R2 并改写 site.ts
#   ./do.sh screenshots --check     # 只检查 site.ts 是否指向当前截图
#   ./do.sh data                    # 交互：check / gen / dict
#   ./do.sh data check|gen|dict     # 直跑
#   ./do.sh doctor                  # 检查 Flutter / Java / .env / adb / 签名
#
# 环境变量（可选）:
#   ANDROID_SERIAL / SERIAL   adb 设备
#   ZHIPU_API_KEY 等          见 .env.example（release / install --release 需要）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
# shellcheck source=scripts/lib/prompt-menu.sh
source "$ROOT/scripts/lib/prompt-menu.sh"
LOG_TAG=alice

PACKAGE=com.vvenv.alice
ACTIVITY=com.vvenv.alice.MainActivity
SERIAL="${ANDROID_SERIAL:-${SERIAL:-}}"

VERSION_ROOT="$ROOT"
# shellcheck source=scripts/lib/version.sh
source "$ROOT/scripts/lib/version.sh"

usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

need() {
  command -v "$1" >/dev/null 2>&1 || log_die "需要 $1 在 PATH 上"
}

load_env() {
  if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
  fi
}

prompt_confirm() {
  local message="$1"
  local default="${2:-y}"

  if [ ! -t 0 ]; then
    [ "$default" = "y" ]
    return
  fi

  local hint="Y/n"
  if [ "$default" = "n" ]; then
    hint="y/N"
  fi

  local answer=""
  read -r -p "$message [$hint]: " answer </dev/tty || true
  if [ -z "$answer" ]; then
    answer="$default"
  fi
  case "$answer" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

pause_menu() {
  [ -t 0 ] || return 0
  echo ""
  read -r -p "按回车返回菜单…" _ </dev/tty || true
}

# ---------- JDK（与 release.sh 对齐）----------

ensure_java() {
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    return
  fi
  local jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  local hb17="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  if [ -d "$jbr" ]; then
    export JAVA_HOME="$jbr"
  elif [ -d "$hb17" ]; then
    export JAVA_HOME="$hb17"
  fi
}

# ---------- SDK / adb ----------

find_sdk() {
  if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
    printf '%s\n' "$ANDROID_HOME"
    return
  fi
  if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return
  fi
  if [ -f "$ROOT/android/local.properties" ]; then
    local d
    d=$(sed -n 's/^sdk.dir=//p' "$ROOT/android/local.properties" | tail -1)
    if [ -n "$d" ] && [ -d "$d" ]; then
      printf '%s\n' "$d"
      return
    fi
  fi
  local d
  for d in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" "$HOME/android-sdk"; do
    if [ -d "$d" ]; then
      printf '%s\n' "$d"
      return
    fi
  done
}

ensure_adb() {
  if command -v adb >/dev/null 2>&1; then
    return
  fi
  local sdk
  sdk=$(find_sdk)
  if [ -n "$sdk" ] && [ -x "$sdk/platform-tools/adb" ]; then
    export PATH="$sdk/platform-tools:$PATH"
    export ANDROID_HOME="$sdk"
    export ANDROID_SDK_ROOT="$sdk"
    return
  fi
  log_die "找不到 adb。请先安装 Android Studio 并打开一次（会装 SDK），再重试。"
}

adb_cmd() {
  if [ -n "$SERIAL" ]; then
    adb -s "$SERIAL" "$@"
  else
    adb "$@"
  fi
}

online_serials() {
  adb devices | awk 'NR>1 && $2=="device" {print $1}'
}

device_menu_label() {
  local s="$1"
  local model
  model=$(adb -s "$s" shell getprop ro.product.model 2>/dev/null | tr -d '\r') || model=""
  case "$s" in
    emulator-*)
      if [ -n "$model" ]; then
        printf '%s  %s（模拟器）\n' "$s" "$model"
      else
        printf '%s（模拟器）\n' "$s"
      fi
      ;;
    *)
      if [ -n "$model" ]; then
        printf '%s  %s\n' "$s" "$model"
      else
        printf '%s\n' "$s"
      fi
      ;;
  esac
}

choose_serial() {
  local title="$1"
  shift
  local opts=() i=1 s idx
  for s in "$@"; do
    opts+=("${i}:$(device_menu_label "$s")")
    i=$((i + 1))
  done
  idx="$(prompt_menu "$title" --default=1 "${opts[@]}")"
  i=1
  for s in "$@"; do
    if [ "$i" -eq "$idx" ]; then
      SERIAL="$s"
      return
    fi
    i=$((i + 1))
  done
}

pick_device() {
  ensure_adb
  if [ -n "$SERIAL" ]; then
    if adb_cmd get-state >/dev/null 2>&1; then
      return
    fi
    log_warn "指定的设备 $SERIAL 已离线，重新选择。"
    SERIAL=""
  fi

  set -- $(online_serials)
  if [ $# -eq 0 ]; then
    log_die "没有设备。请连上真机（USB 调试）或先开模拟器，再跑 flutter devices 核对。"
  fi
  if [ $# -eq 1 ]; then
    SERIAL="$1"
    log_info "使用设备 $SERIAL"
    return
  fi
  if [ ! -t 0 ]; then
    log_error "多台设备，请传 -s SERIAL:"
    printf '  %s\n' "$@" >&2
    exit 1
  fi
  choose_serial "装到哪台设备" "$@"
  log_info "使用设备 $SERIAL"
}

# ---------- 子命令 ----------

cmd_run() {
  local device=""
  local extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --chrome) device=chrome ;;
      -d|--device)
        shift
        [ $# -gt 0 ] || log_die "缺少 -d 后的设备 id"
        device="$1"
        ;;
      -h|--help) usage 0 ;;
      *)
        extra+=("$1")
        ;;
    esac
    shift
  done

  need flutter
  load_env
  ensure_java

  local args=()
  if [ -n "$device" ]; then
    args+=(-d "$device")
  fi
  if [ ${#extra[@]} -gt 0 ]; then
    args+=("${extra[@]}")
  fi

  if [ -n "${ZHIPU_API_KEY:-}" ]; then
    args+=(--dart-define="ZHIPU_API_KEY=${ZHIPU_API_KEY}")
  fi

  log_info "flutter run ${args[*]:-}"
  # shellcheck disable=SC2086
  flutter run ${args[@]+"${args[@]}"}
}

cmd_test() {
  local do_lint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --lint) do_lint=1 ;;
      -h|--help) usage 0 ;;
      *) log_die "test 未知参数: $1" ;;
    esac
    shift
  done

  if [ -t 0 ] && [ "$do_lint" -eq 0 ]; then
    local ans
    ans="$(prompt_menu "跑哪些检查" --default=1 \
      "flutter:analyze + test" \
      "all:analyze + test + pnpm lint")"
    [ "$ans" = "all" ] && do_lint=1
  fi

  need flutter
  log_info "flutter analyze"
  flutter analyze
  log_info "flutter test"
  flutter test
  if [ "$do_lint" -eq 1 ]; then
    need pnpm
    log_info "pnpm lint"
    pnpm lint
  fi
  log_success "测试完成"
}

cmd_install() {
  local build=debug
  local launch=1
  local launch_preset=0
  local build_preset=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --debug) build=debug; build_preset=1 ;;
      --release) build=release; build_preset=1 ;;
      --launch) launch=1; launch_preset=1 ;;
      --no-launch) launch=0; launch_preset=1 ;;
      -s|--serial)
        shift
        [ $# -gt 0 ] || log_die "缺少 -s 后的设备号"
        SERIAL="$1"
        ;;
      -h|--help) usage 0 ;;
      *) log_die "install 未知参数: $1" ;;
    esac
    shift
  done

  if [ -t 0 ] && [ "$build_preset" -eq 0 ]; then
    build="$(prompt_menu "安装包" --default=1 \
      "debug:开发版" \
      "release:正式版")"
  fi
  if [ -t 0 ] && [ "$launch_preset" -eq 0 ]; then
    local l
    l="$(prompt_menu "装完打开？" --default=2 \
      "no:不打开" \
      "yes:打开")"
    if [ "$l" = "yes" ]; then launch=1; else launch=0; fi
  fi

  need flutter
  load_env
  ensure_java
  pick_device

  local define_args=()
  if [ "$build" = release ]; then
    : "${ZHIPU_API_KEY:?ZHIPU_API_KEY not set — add it to .env (see .env.example)}"
    define_args+=(--dart-define="ZHIPU_API_KEY=${ZHIPU_API_KEY}")
    if [ ! -f "$ROOT/android/key.properties" ]; then
      log_warn "未找到 android/key.properties，release APK 将使用 debug 签名"
    fi
  fi

  log_info "编译 ${build} APK…"
  if [ "$build" = release ]; then
    flutter build apk --release --split-per-abi --target-platform android-arm64 \
      ${define_args[@]+"${define_args[@]}"}
    APK="$ROOT/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
  else
    flutter build apk --debug
    APK="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  fi
  [ -f "$APK" ] || log_die "找不到安装包: $APK"

  log_info "安装到 $SERIAL ($(du -h "$APK" | awk '{print $1}'))"
  adb_cmd install -r "$APK"
  if [ "$launch" -eq 1 ]; then
    log_info "打开 Alice 听写"
    adb_cmd shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null
  fi
  log_success "完成（${build} → ${SERIAL}）"
}

cmd_release() {
  local bump=""
  while [ $# -gt 0 ]; do
    case "$1" in
      keep|none|"")
        bump=""
        ;;
      patch|minor|major)
        bump="$1"
        ;;
      -h|--help) usage 0 ;;
      *)
        if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          bump="$1"
        else
          log_die "release 未知参数: $1（可用 keep / patch / minor / major / x.y.z）"
        fi
        ;;
    esac
    shift
  done

  local current
  current="$(get_current_version)"

  if [ -z "$bump" ] && [ -t 0 ]; then
    local next_patch next_minor next_major how major minor patch
    IFS=. read -r major minor patch <<<"$current"
    next_patch="${major}.${minor}.$((patch + 1))"
    next_minor="${major}.$((minor + 1)).0"
    next_major="$((major + 1)).0.0"
    how="$(prompt_menu "Android 发版版本" --default=2 \
      "keep:保持 ${current}" \
      "patch:升 patch → ${next_patch}" \
      "minor:升 minor → ${next_minor}" \
      "major:升 major → ${next_major}" \
      "set:手动输入")"
    case "$how" in
      keep) bump="" ;;
      patch|minor|major) bump="$how" ;;
      set)
        local ans=""
        read -r -p "版本号 [${current}]: " ans </dev/tty || true
        if [ -n "$ans" ] && [ "$ans" != "$current" ]; then
          bump="$ans"
        else
          bump=""
        fi
        ;;
    esac
  elif [ -z "$bump" ] && [ ! -t 0 ]; then
    bump=patch
    log_info "非交互：默认升 patch"
  fi

  if [ -t 0 ]; then
    echo ""
    if [ -n "$bump" ]; then
      log_info "将执行: bash scripts/release.sh ${bump}"
    else
      log_info "将执行: bash scripts/release.sh（保持 ${current}）"
    fi
    echo ""
    if ! prompt_confirm "开始发版？" "y"; then
      log_info "已取消"
      return 0
    fi
  fi

  if [ -n "$bump" ]; then
    bash "$ROOT/scripts/release.sh" "$bump"
  else
    bash "$ROOT/scripts/release.sh"
  fi
}

cmd_website() {
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --skip-webapp) args+=(--skip-webapp) ;;
      -h|--help) usage 0 ;;
      *) log_die "website 未知参数: $1" ;;
    esac
    shift
  done

  if [ -t 0 ] && [ ${#args[@]} -eq 0 ]; then
    local ans
    ans="$(prompt_menu "官网部署" --default=1 \
      "all:落地页 + /app/" \
      "skip:仅落地页")"
    [ "$ans" = "skip" ] && args+=(--skip-webapp)
  fi

  log_info "部署官网…"
  bash "$ROOT/scripts/release-website.sh" ${args[@]+"${args[@]}"}
}

cmd_webapp() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage 0 ;;
      *) log_die "webapp 未知参数: $1" ;;
    esac
    shift
  done
  log_info "部署 Web 应用 /app/…"
  bash "$ROOT/scripts/release-webapp.sh"
}

cmd_screenshots() {
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --check) args+=(--check) ;;
      -h|--help) usage 0 ;;
      *) log_die "screenshots 未知参数: $1" ;;
    esac
    shift
  done

  need pnpm
  if [ ${#args[@]} -gt 0 ]; then
    bash "$ROOT/scripts/upload-screenshots.sh" --check
    return
  fi
  log_info "上传截图…"
  bash "$ROOT/scripts/upload-screenshots.sh"
  log_success "截图已上传；部署官网后生效"
}

cmd_data() {
  local which="${1:-}"
  if [ -n "$which" ]; then
    shift
  fi
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage 0 ;;
      *) log_die "data 多余参数: $1" ;;
    esac
    shift
  done

  if [ -z "$which" ] && [ -t 0 ]; then
    which="$(prompt_menu "数据任务" --default=1 \
      "check:校验 data/" \
      "gen:生成 library.json" \
      "dict:构建 ecdict-meta")"
  fi
  which="${which:-check}"

  need pnpm
  case "$which" in
    check)
      log_info "pnpm data:check"
      pnpm data:check
      ;;
    gen)
      log_info "pnpm data:gen"
      pnpm data:gen
      ;;
    dict)
      log_info "pnpm dict:build"
      pnpm dict:build
      ;;
    *)
      log_die "未知 data 任务: ${which}（check / gen / dict）"
      ;;
  esac
  log_success "data ${which} 完成"
}

cmd_doctor() {
  local ok=1
  echo "Alice 环境检查"
  echo "--------------"

  if command -v flutter >/dev/null 2>&1; then
    echo "  ✓ flutter  $(flutter --version 2>/dev/null | head -1)"
  else
    echo "  ✗ flutter  不在 PATH"
    ok=0
  fi

  ensure_java || true
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    echo "  ✓ JAVA_HOME  $JAVA_HOME"
    echo "      $("${JAVA_HOME}/bin/java" -version 2>&1 | head -1)"
  elif command -v java >/dev/null 2>&1; then
    echo "  ⚠ java      在 PATH（建议 JDK 17/21；JDK 25+ 会挂）"
    java -version 2>&1 | head -1 | sed 's/^/      /'
  else
    echo "  ✗ java      找不到"
    ok=0
  fi

  if [ -f "$ROOT/.env" ]; then
    echo "  ✓ .env"
    load_env
    local k
    for k in ZHIPU_API_KEY DEPLOY_SERVER DEPLOY_REMOTE_DIR R2_BUCKET R2_PUBLIC_BASE CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN; do
      if [ -n "${!k:-}" ]; then
        echo "      ✓ $k"
      else
        echo "      ✗ $k  未设置"
        ok=0
      fi
    done
  else
    echo "  ✗ .env  不存在（cp .env.example .env）"
    ok=0
  fi

  if ! command -v adb >/dev/null 2>&1; then
    local sdk
    sdk=$(find_sdk)
    if [ -n "$sdk" ] && [ -x "$sdk/platform-tools/adb" ]; then
      export PATH="$sdk/platform-tools:$PATH"
    fi
  fi
  if command -v adb >/dev/null 2>&1; then
    echo "  ✓ adb     $(command -v adb)"
    local devices
    devices=$(online_serials | tr '\n' ' ')
    if [ -n "$devices" ]; then
      echo "      在线: $devices"
    else
      echo "      （当前无已授权设备）"
    fi
  else
    echo "  ✗ adb     找不到"
    ok=0
  fi

  if [ -f "$ROOT/android/key.properties" ]; then
    echo "  ✓ android/key.properties  （正式签名）"
  else
    echo "  ⚠ android/key.properties  缺失 → release 用 debug 签名"
  fi

  echo "  版本    $(get_current_version)+$(get_current_version_code)"

  if [ "$ok" -eq 1 ]; then
    log_success "环境看起来正常"
  else
    log_warn "有未就绪项，发版前请先补齐"
    return 1
  fi
}

run_main_menu() {
  while true; do
    local choice
    choice="$(prompt_menu "做什么" --default=1 \
      "run:运行 App" \
      "test:分析 + 测试" \
      "install:编译并安装" \
      "release:Android 发版" \
      "website:部署官网" \
      "webapp:部署 /app/" \
      "screenshots:上传截图" \
      "data:词库数据" \
      "doctor:环境检查" \
      "quit:退出")"
    case "$choice" in
      quit)
        exit 0
        ;;
      run|test|install|release|website|webapp|screenshots|data|doctor)
        "cmd_$choice" || true
        pause_menu
        ;;
      *)
        log_die "未知命令: $choice"
        ;;
    esac
  done
}

# ---------- 入口 ----------

CMD=""
if [ $# -gt 0 ]; then
  case "$1" in
    -h|--help) usage 0 ;;
    run|test|install|release|website|webapp|screenshots|data|doctor)
      CMD="$1"
      shift
      ;;
    -*)
      log_die "请先给出子命令（run / test / install / release …），或直接运行 ./do.sh"
      ;;
    *)
      echo "未知命令: $1" >&2
      usage 2
      ;;
  esac
fi

if [ -z "$CMD" ]; then
  if [ -t 0 ]; then
    run_main_menu
  else
    usage 2
  fi
else
  "cmd_$CMD" "$@"
fi
