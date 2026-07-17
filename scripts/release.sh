#!/usr/bin/env bash
# One-click Android release: (optional) bump version → build APK → stage on website → publish.
#
# Flow:
#   0. Optionally bump version (patch / minor / major / x.y.z)
#   1. Read version from app.json
#   2. Build the APK locally via EAS (--local, preview profile) to a temp path
#   3. Move it to website/public/downloads/alice-<version>-<timestamp>.apk
#      (removing any previous timestamped APK there)
#   4. Update APK_URL in website/src/components/Download.tsx
#   5. Build the website (pnpm --filter website build)
#   6. Deploy dist/ to the server via rsync. If the new APK's bytes already
#      exist on the server (same sha256), rename it in place and skip the
#      ~89 MB upload; otherwise upload everything.
#
# Usage:
#   pnpm release:android              # build + deploy (keep current version)
#   pnpm release:android patch        # bump patch (0.2.0 → 0.2.1) then release
#   pnpm release:android minor        # bump minor (0.2.0 → 0.3.0) then release
#   pnpm release:android major        # bump major (0.2.0 → 1.0.0) then release
#   pnpm release:android 0.3.0        # set explicit version then release
#   bash scripts/release.sh patch     # same, directly
#
# Prereqs: EAS CLI authenticated, Java 17+ / Android SDK for --local builds,
#          SSH key auth to the deploy server (BatchMode).
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

# --- args ---
VERSION_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      sed -n '3,24p' "$0"
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
# Deploy target comes from the gitignored .env (or the environment):
#   DEPLOY_SERVER=user@your.server.ip
#   DEPLOY_REMOTE_DIR=/var/www/alice
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
DOWNLOAD_TSX="$WEBSITE_DIR/src/components/Download.tsx"
APK_PUBLIC_DIR="$WEBSITE_DIR/public/downloads"

# --- 0. optional version bump ---
if [ -n "$VERSION_ARG" ]; then
  CURRENT="$(get_current_version)"
  NEW_VERSION="$(resolve_version "$VERSION_ARG")" || error "无法解析版本: $VERSION_ARG"
  NEW_CODE="$(sync_versions "$NEW_VERSION")"
  echo "▶ Bumped version $CURRENT → $NEW_VERSION (versionCode $NEW_CODE)"
  echo ""
fi

# --- read version + timestamp ---
VERSION="$(node -p "require('./app.json').expo.version")"
TS="$(date +%Y%m%d-%H%M)"
APK_NAME="alice-${VERSION}-${TS}.apk"
APK_PUBLIC="$APK_PUBLIC_DIR/$APK_NAME"
APK_URL="$PUBLIC_HOST/downloads/$APK_NAME"

echo "▶ Releasing Alice v$VERSION ($TS)"
echo "  APK file: $APK_NAME"
echo ""

# --- 1. build APK ---
TMP_DIR="$(mktemp -d)"
TMP_APK="$TMP_DIR/alice.apk"
trap 'rm -rf "$TMP_DIR"' EXIT
echo "▶ [1/6] Building APK via EAS (local, preview)..."
# Call eas directly (not via `pnpm build:android:local -- ...`): pnpm forwards the
# `--` separator to eas, which then treats --output as a positional arg and
# rejects it. `pnpm exec` resolves the eas binary without that separator.
pnpm exec eas build \
  --platform android --non-interactive --local --profile preview \
  --output "$TMP_APK"
echo "  built: $(du -h "$TMP_APK" | cut -f1) → $TMP_APK"

# --- 2. stage APK on website ---
echo "▶ [2/6] Staging APK on website..."
mkdir -p "$APK_PUBLIC_DIR"
# remove previous timestamped APK(s); keep nothing stale
find "$APK_PUBLIC_DIR" -maxdepth 1 -name 'alice-*.apk' -delete
mv "$TMP_APK" "$APK_PUBLIC"
echo "  staged at website/public/downloads/$APK_NAME"

# --- 3. update APK_URL ---
echo "▶ [3/6] Updating APK_URL in Download.tsx..."
APK_URL="$APK_URL" perl -pi -e 's{https://alice\.edao\.plus/downloads/alice-[^"]+\.apk}{$ENV{APK_URL}}g' "$DOWNLOAD_TSX"
echo "  → $APK_URL"

# --- 4. build website ---
echo "▶ [4/6] Building website..."
pnpm --filter website build

# --- 5. deploy ---
echo "▶ [5/6] Deploying to $SERVER:$REMOTE_DIR..."
LOCAL_APK="$WEBSITE_DIR/dist/downloads/$APK_NAME"
LOCAL_SHA="$(shasum -a 256 "$LOCAL_APK" | cut -d' ' -f1)"
RSYNC_EXCLUDE=""

# compare with whatever APK already lives on the server
EXISTING="$(ssh -o BatchMode=yes "$SERVER" "ls $REMOTE_DIR/downloads/*.apk 2>/dev/null | head -1" 2>/dev/null || true)"
if [ -n "$EXISTING" ]; then
  REMOTE_SHA="$(ssh -o BatchMode=yes "$SERVER" "sha256sum '$EXISTING'" | cut -d' ' -f1)"
  if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
    echo "  server APK bytes identical (sha ${LOCAL_SHA:0:12}...) → rename in place, skip upload"
    ssh -o BatchMode=yes "$SERVER" "mv '$EXISTING' '$REMOTE_DIR/downloads/$APK_NAME'"
    RSYNC_EXCLUDE="--exclude=downloads"
  else
    echo "  server APK differs (local ${LOCAL_SHA:0:12}... vs remote ${REMOTE_SHA:0:12}...) → upload new APK"
  fi
else
  echo "  no APK on server yet → upload"
fi

rsync -avz --delete $RSYNC_EXCLUDE "$WEBSITE_DIR/dist/" "$SERVER:$REMOTE_DIR/"

# --- 6. verify ---
echo "▶ [6/6] Verifying..."
ssh -o BatchMode=yes "$SERVER" \
  "curl -s -o /dev/null -w '  /downloads/$APK_NAME → HTTP %{http_code}, %{size_download} B, %{content_type}\n' $PUBLIC_HOST/downloads/$APK_NAME"

echo ""
echo "✓ Released v$VERSION ($TS)"
echo "  APK:  $PUBLIC_HOST/downloads/$APK_NAME"
echo "  Site: $PUBLIC_HOST/#download"
echo ""
echo "Reminder: review & commit when ready —"
if [ -n "$VERSION_ARG" ]; then
  echo "  git add package.json app.json android/app/build.gradle ios/Alice.xcodeproj/project.pbxproj \\"
  echo "         website/src/components/Download.tsx"
else
  echo "  git add website/src/components/Download.tsx"
fi
echo "  (APK is gitignored; only the URL change in Download.tsx is tracked)"
