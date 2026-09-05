#!/usr/bin/env bash
# One-click Android release: (optional) bump version → build APK → upload to
# Cloudflare R2 → publish website.
#
# Flow:
#   0. Optionally bump version (patch / minor / major / x.y.z)
#   1. Read version from pubspec.yaml
#   2. Build the release APK with `flutter build apk` to a temp path
#   3. Upload it to Cloudflare R2 (wrangler) as alice-<version>-<timestamp>.apk
#      — zero egress fees, and the deploy server no longer carries ~110 MB APKs
#   4. Update APK_URL in website/src/data/site.ts (and public/llms.txt)
#   5. Build the website (pnpm --filter website build)
#   6. Deploy dist/ to the server via rsync (excluding app/). The legacy
#      downloads/ dir on the server is removed by --delete — APKs live on R2.
#
# Usage:
#   pnpm release:android              # build + deploy (keep current version)
#   pnpm release:android patch        # bump patch (0.2.0 → 0.2.1) then release
#   pnpm release:android minor        # bump minor (0.2.0 → 0.3.0) then release
#   pnpm release:android major        # bump major (0.2.0 → 1.0.0) then release
#   pnpm release:android 0.3.0        # set explicit version then release
#   bash scripts/release.sh patch     # same, directly
#
# Prereqs: Flutter SDK on PATH, Java 17 or 21 (NOT 25+ — JEP 472 breaks AGP
#          CMake configure) / Android SDK,
#          ZHIPU_API_KEY in .env (compiled into the APK; never into the web
#          build — see scripts/release-webapp.sh),
#          SSH key auth to the deploy server (BatchMode),
#          R2 bucket + API token configured in .env (see .env.example):
#            R2_BUCKET / R2_PUBLIC_BASE / CLOUDFLARE_ACCOUNT_ID /
#            CLOUDFLARE_API_TOKEN
#          This script auto-selects Android Studio's JBR (JDK 21) or Homebrew
#          openjdk@17 when JAVA_HOME is unset.
#
# NOTE: The QR code is intentionally NOT touched — it encodes the stable
# URL https://alice.edao.plus/#download, so it never needs regenerating.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/version.sh
VERSION_ROOT="$ROOT"
source "$ROOT/scripts/lib/version.sh"

error() { echo "ERROR: $*" >&2; exit 1; }

# 核对 APK 里 manifest 声明的启动 Activity 真的存在于 classes.dex。
# 见 README「出包自检」：这一条错了只有真机启动时才看得出来。
verify_launch_activity() {
  local apk="$1" aapt fqcn
  aapt="$(ls "$HOME"/Library/Android/sdk/build-tools/*/aapt2 2>/dev/null | tail -1)"
  if [ -z "$aapt" ]; then
    echo "  ⚠ 找不到 aapt2，跳过启动 Activity 自检" >&2
    return 0
  fi
  fqcn="$("$aapt" dump badging "$apk" | sed -n "s/^launchable-activity: name='\\([^']*\\)'.*/\\1/p")"
  [ -n "$fqcn" ] || error "APK 里没有 launchable-activity"
  if ! unzip -p "$apk" 'classes*.dex' | LC_ALL=C grep -qa "L${fqcn//./\/};"; then
    error "启动 Activity $fqcn 不在 classes.dex 里 —— 这个包装上去会闪退"
  fi
  echo "  启动 Activity: $fqcn ✓"
}

# --- args ---
VERSION_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      sed -n '5,31p' "$0"
      exit 0
      ;;
    -*)
      error "未知选项: $1（可用 patch / minor / major / x.y.z）"
      ;;
    *)
      if [ -n "$VERSION_ARG" ]; then
        error "多余的参数: $1"
      fi
      VERSION_ARG="$1"
      shift
      ;;
  esac
done

# --- config ---
# Deploy target and R2 credentials come from the gitignored .env (or the
# environment):
#   DEPLOY_SERVER=user@your.server.ip
#   DEPLOY_REMOTE_DIR=/var/www/alice
#   R2_BUCKET=alice-apk
#   R2_PUBLIC_BASE=https://pub-xxxxxxxx.r2.dev  (or a custom domain)
#   CLOUDFLARE_ACCOUNT_ID=your-cloudflare-account-id
#   CLOUDFLARE_API_TOKEN=your-r2-api-token      (Account → R2 → Edit)
if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi
SERVER="${DEPLOY_SERVER:?DEPLOY_SERVER not set — add it to .env (see .env.example)}"
REMOTE_DIR="${DEPLOY_REMOTE_DIR:-/var/www/alice}"
PUBLIC_HOST="https://alice.edao.plus"
WEBSITE_DIR="$ROOT/website"
APK_PUBLIC_DIR="$WEBSITE_DIR/public/downloads"
R2_BUCKET="${R2_BUCKET:?R2_BUCKET not set — add it to .env (see .env.example)}"
R2_PUBLIC_BASE="${R2_PUBLIC_BASE:?R2_PUBLIC_BASE not set — add it to .env (see .env.example)}"
R2_PUBLIC_BASE="${R2_PUBLIC_BASE%/}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID not set — add it to .env (see .env.example)}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN not set — add it to .env (see .env.example)}"

# --- JDK for Gradle ---
# JDK 25+ restricts native access in java.lang.System (JEP 472) and breaks
# AGP's CMake configure step ("A restricted method in java.lang.System has
# been called"). Pick Android Studio's bundled JBR (JDK 21), then Homebrew
# openjdk@17, before falling back to whatever java is on PATH.
if [ -z "${JAVA_HOME:-}" ]; then
  JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  HB17="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  if [ -d "$JBR" ]; then
    export JAVA_HOME="$JBR"
  elif [ -d "$HB17" ]; then
    export JAVA_HOME="$HB17"
  fi
fi
echo "  JDK: ${JAVA_HOME:-(system java on PATH — needs JDK 17/21; JDK 25+ will fail)}"

# --- 0. optional version bump ---
if [ -n "$VERSION_ARG" ]; then
  CURRENT="$(get_current_version)"
  NEW_VERSION="$(resolve_version "$VERSION_ARG")" || error "无法解析版本: $VERSION_ARG"
  NEW_CODE="$(sync_versions "$NEW_VERSION")"
  echo "▶ Bumped version $CURRENT → $NEW_VERSION (versionCode $NEW_CODE)"
  echo ""
fi

# --- read version + timestamp ---
VERSION="$(get_current_version)"
TS="$(date +%Y%m%d-%H%M)"
APK_NAME="alice-${VERSION}-${TS}.apk"
APK_URL="$R2_PUBLIC_BASE/$APK_NAME"

echo "▶ Releasing Alice v$VERSION ($TS)"
echo "  APK object: $R2_BUCKET/$APK_NAME"
echo ""

# --- 1. build APK ---
TMP_DIR="$(mktemp -d)"
TMP_APK="$TMP_DIR/alice.apk"
trap 'rm -rf "$TMP_DIR"' EXIT
echo "▶ [1/6] Building release APK..."
# OCR 密钥走编译期常量。Web 构建不传（产物是公开 JS），这里必须传。
: "${ZHIPU_API_KEY:?ZHIPU_API_KEY not set — add it to .env (see .env.example)}"
flutter build apk --release --dart-define=ZHIPU_API_KEY="$ZHIPU_API_KEY"
BUILT_APK="build/app/outputs/flutter-apk/app-release.apk"
[ -f "$BUILT_APK" ] || error "flutter build 没有产出 $BUILT_APK"
cp "$BUILT_APK" "$TMP_APK"

# manifest 声明的启动 Activity 必须真的打进 dex —— 少了它编译期毫无征兆，
# 装到手机上必然 ClassNotFoundException 闪退（0.6.2 就栽在这里）。
verify_launch_activity "$TMP_APK"

echo "  built: $(du -h "$TMP_APK" | cut -f1) → $TMP_APK"

# --- 2. upload APK to Cloudflare R2 ---
echo "▶ [2/6] Uploading APK to R2 bucket '$R2_BUCKET'..."
# Versioned objects are immutable → cache forever. The Android MIME type makes
# browsers offer to install instead of downloading an octet-stream.
pnpm exec wrangler r2 object put "$R2_BUCKET/$APK_NAME" \
  --file "$TMP_APK" \
  --remote \
  --content-type "application/vnd.android.package-archive" \
  --cache-control "public, max-age=31536000, immutable"
echo "  uploaded → $APK_URL"
# Purge APKs staged by the pre-R2 flow so they never re-enter the website build.
mkdir -p "$APK_PUBLIC_DIR"
find "$APK_PUBLIC_DIR" -maxdepth 1 -name 'alice-*.apk' -delete

# --- 3. update APK_URL ---
SITE_TS="$WEBSITE_DIR/src/data/site.ts"
LLMS_TXT="$WEBSITE_DIR/public/llms.txt"
echo "▶ [3/6] Updating APK_URL in site.ts / llms.txt..."
# site.ts has the URL on its own line after `export const APK_URL =`, so slurp
# the whole file (-0777) to match across the line break.
APK_URL="$APK_URL" perl -0777 -pi -e 's{(export const APK_URL\s*=\s*")[^"]+(")}{$1$ENV{APK_URL}$2}' "$SITE_TS"
VERSION="$VERSION" perl -pi -e 's{(export const APP_VERSION\s*=\s*")[^"]+(")}{$1$ENV{VERSION}$2}' "$SITE_TS"
APK_URL="$APK_URL" perl -pi -e 's{https://[^"\s]+/alice-[^"\s]+\.apk}{$ENV{APK_URL}}g' "$LLMS_TXT"
echo "  → $APK_URL"

# --- 4. build website ---
echo "▶ [4/6] Building website..."
pnpm --filter website build

# --- 5. deploy website ---
# Always preserve the Web app under /app/ (deployed separately).
# downloads/ is intentionally NOT excluded anymore: the APK lives on R2 now,
# so --delete also cleans up the legacy server copy in one go.
echo "▶ [5/6] Deploying website to $SERVER:$REMOTE_DIR..."
rsync -avz --delete --exclude=app \
  -e "ssh -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o TCPKeepAlive=yes" \
  "$WEBSITE_DIR/dist/" "$SERVER:$REMOTE_DIR/"

# --- 6. verify ---
echo "▶ [6/6] Verifying..."
curl -sS --head -o /dev/null -w "  APK  → HTTP %{http_code}, %{content_type}\n" "$APK_URL"
curl -sS -o /dev/null -w "  Site → HTTP %{http_code}\n" "$PUBLIC_HOST/"

echo ""
echo "✓ Released v$VERSION ($TS)"
echo "  APK:  $APK_URL"
echo "  Site: $PUBLIC_HOST/#download"
echo ""
echo "Reminder: review & commit when ready —"
if [ -n "$VERSION_ARG" ]; then
  echo "  git add pubspec.yaml website/src/data/site.ts website/public/llms.txt"
else
  echo "  git add website/src/data/site.ts website/public/llms.txt"
fi
echo "  (APK is gitignored; only the URL changes are tracked)"
