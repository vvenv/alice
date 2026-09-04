#!/usr/bin/env bash
# 生成并配置 Flutter 平台目录（android/ ios/ web/）。
#
# `flutter create .` 只会补出缺失的平台脚手架，不动已有的 lib/ 与 assets/。
# 之后这个脚本把 RN 版 app.json 里的应用身份与权限配置搬过来：
#
#   - applicationId / bundleIdentifier 保持 com.vvenv.alice
#     ★ 这一条是硬要求：包名变了就是另一个 app 沙箱，
#       services/legacy_migration_io.dart 将读不到 RN 版的 AsyncStorage，
#       老用户的错词本 / 历史 / 收藏 / Credits 会全部丢失。
#   - 应用名「Alice 听写」
#   - Android 权限：CAMERA / RECORD_AUDIO / MODIFY_AUDIO_SETTINGS /
#     FOREGROUND_SERVICE / FOREGROUND_SERVICE_MEDIA_PLAYBACK / INTERNET
#   - iOS：相机与相册用途说明、后台音频
#
# 幂等：可以重复执行。
#
# 用法：bash scripts/bootstrap.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_ID="com.vvenv.alice"
APP_NAME="Alice 听写"

error() { echo "ERROR: $*" >&2; exit 1; }
step() { echo "==> $*"; }

command -v flutter >/dev/null 2>&1 || error "找不到 flutter，请先安装 Flutter SDK"

step "生成平台目录"
flutter create . --org com.vvenv --project-name alice_dictation --platforms=android,ios,web

step "拉取依赖"
flutter pub get

# --- Android --------------------------------------------------------------

GRADLE="android/app/build.gradle.kts"
[ -f "$GRADLE" ] || GRADLE="android/app/build.gradle"
[ -f "$GRADLE" ] || error "找不到 android/app/build.gradle[.kts]"

step "Android: applicationId → $APP_ID"
# flutter create 生成的是 com.vvenv.alice_dictation，改回 RN 版的包名，
# 这样才是同一个 app 的升级，老数据也才读得到。
perl -0pi -e "s/com\.vvenv\.alice_dictation/$APP_ID/g" "$GRADLE"
perl -0pi -e "s/com\.vvenv\.alice_dictation/$APP_ID/g" \
  android/app/src/main/AndroidManifest.xml 2>/dev/null || true

MANIFEST="android/app/src/main/AndroidManifest.xml"
step "Android: 权限与应用名"
python3 - "$MANIFEST" "$APP_NAME" <<'PY'
import re, sys

path, app_name = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()

perms = [
    "android.permission.INTERNET",
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.MODIFY_AUDIO_SETTINGS",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
]

missing = [p for p in perms if f'android:name="{p}"' not in src]
if missing:
    block = "\n".join(
        f'    <uses-permission android:name="{p}"/>' for p in missing
    )
    src = src.replace("<manifest", "<manifest", 1)
    src = re.sub(r"(<manifest[^>]*>)", r"\1\n" + block, src, count=1)

# 应用名
src = re.sub(
    r'android:label="[^"]*"', f'android:label="{app_name}"', src, count=1
)

open(path, "w", encoding="utf-8").write(src)
print(f"  权限补齐: {missing or '（已齐全）'}")
PY

# --- iOS ------------------------------------------------------------------

PLIST="ios/Runner/Info.plist"
[ -f "$PLIST" ] || error "找不到 $PLIST"

step "iOS: bundle id → $APP_ID"
perl -0pi -e "s/com\.vvenv\.alice_dictation/$APP_ID/g" \
  ios/Runner.xcodeproj/project.pbxproj

step "iOS: 用途说明与后台音频"
/usr/libexec/PlistBuddy -c \
  "Set :CFBundleDisplayName $APP_NAME" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c \
    "Add :CFBundleDisplayName string $APP_NAME" "$PLIST"

/usr/libexec/PlistBuddy -c \
  "Set :NSCameraUsageDescription 用于拍摄单词图片进行 OCR 识别" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c \
    "Add :NSCameraUsageDescription string 用于拍摄单词图片进行 OCR 识别" "$PLIST"

/usr/libexec/PlistBuddy -c \
  "Set :NSPhotoLibraryUsageDescription 用于从相册选取单词图片进行 OCR 识别" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c \
    "Add :NSPhotoLibraryUsageDescription string 用于从相册选取单词图片进行 OCR 识别" "$PLIST"

# 后台音频 —— 对应 RN 版 expo-audio 的 enableBackgroundPlayback
if ! /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$PLIST"
fi
if ! /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" | grep -q audio; then
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes: string audio" "$PLIST"
fi

step "完成。接下来："
echo "  flutter analyze"
echo "  flutter run"
