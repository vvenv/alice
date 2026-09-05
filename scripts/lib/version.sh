# Alice 版本号工具（供 release.sh 共用）
# 用法: VERSION_ROOT=/path/to/repo source scripts/lib/version.sh
#
# 唯一的版本号来源是 pubspec.yaml 的那一行：
#
#     version: 0.6.3+11
#              ~~~~~ ~~
#              版本号 versionCode
#
# Android 的 versionName / versionCode 与 iOS 的 MARKETING_VERSION /
# CURRENT_PROJECT_VERSION 都由 Flutter 从这里派生，工程文件里没有第二份拷贝
# 需要同步（这是从 Expo 时代继承下来的教训：那时候有五份，漏掉一份就出事）。
#
# versionCode 只增不减 —— Android 拒绝安装比机器上现有版本低的 versionCode。

if [ -z "${VERSION_ROOT:-}" ]; then
  VERSION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

_pubspec() { echo "$VERSION_ROOT/pubspec.yaml"; }

# 「0.6.3+11」里的 0.6.3
get_current_version() {
  local line
  line="$(grep -m1 '^version:' "$(_pubspec)")" ||
    { echo "pubspec.yaml 里找不到 version:" >&2; return 1; }
  line="${line#version:}"
  line="${line// /}"
  echo "${line%%+*}"
}

# 「0.6.3+11」里的 11
get_current_version_code() {
  local line
  line="$(grep -m1 '^version:' "$(_pubspec)")" ||
    { echo "pubspec.yaml 里找不到 version:" >&2; return 1; }
  line="${line// /}"
  case "$line" in
    *+*) echo "${line##*+}" ;;
    *)   echo 0 ;;
  esac
}

# patch / minor / major / x.y.z → 目标版本号
resolve_version() {
  local arg="$1"
  local current major minor patch
  current="$(get_current_version)"

  case "$arg" in
    patch|minor|major)
      IFS=. read -r major minor patch <<<"$current"
      case "$arg" in
        patch) patch=$((patch + 1)) ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        major) major=$((major + 1)); minor=0; patch=0 ;;
      esac
      arg="$major.$minor.$patch"
      ;;
    *)
      arg="${arg#v}"
      if ! [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "无效的版本号: ${arg}（可用 patch / minor / major / x.y.z）" >&2
        return 1
      fi
      ;;
  esac

  if [ "$arg" = "$current" ]; then
    echo "新版本 $arg 与当前版本相同" >&2
    return 1
  fi
  echo "$arg"
}

# 写回 pubspec.yaml，versionCode 一律 +1。输出新的 versionCode。
sync_versions() {
  local version="$1" code
  code=$(( $(get_current_version_code) + 1 ))
  perl -pi -e "s/^version:.*\$/version: $version+$code/" "$(_pubspec)"
  echo "$code"
}
