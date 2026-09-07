#!/usr/bin/env bash
# 生成并配置 Flutter 平台目录（android/ ios/ web/）。
#
# `flutter create .` 只会补出缺失的平台脚手架，不动已有的 lib/ 与 assets/。
# 之后这个脚本把应用身份与权限写回去 —— 这些是 flutter create 不知道的：
#
#   - applicationId / bundleIdentifier 保持 com.vvenv.alice
#     ★ 这一条是硬要求：包名变了就是另一个 app 沙箱，
#       lib/services/legacy_migration_io.dart 将读不到老的 Expo 版
#       AsyncStorage，老用户的错词本 / 历史 / 收藏 / Credits 会全部丢失。
#       （Expo 实现本身已经删了，见 tag rn-final；但用户手机上还装着它。）
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
# flutter create 会重写它认为属于脚手架的文件（.gitignore、analysis_options.yaml），
# 先备份再还原 —— 我们这两份是手工调过的。
BACKUP="$(mktemp -d)"
for f in .gitignore analysis_options.yaml; do
  [ -f "$f" ] && cp "$f" "$BACKUP/"
done

flutter create . --org com.vvenv --project-name alice_dictation --platforms=android,ios,web

for f in .gitignore analysis_options.yaml; do
  [ -f "$BACKUP/$f" ] && cp "$BACKUP/$f" "$f"
done
rm -rf "$BACKUP"

step "拉取依赖"
flutter pub get

# --- Android --------------------------------------------------------------

GRADLE="android/app/build.gradle.kts"
[ -f "$GRADLE" ] || GRADLE="android/app/build.gradle"
[ -f "$GRADLE" ] || error "找不到 android/app/build.gradle[.kts]"

step "Android: applicationId → $APP_ID"
# flutter create 按 --org + --project-name 拼出 com.vvenv.alice_dictation，
# 改回历史包名，这样才算同一个 app 的升级，老数据也才读得到。
perl -0pi -e "s/com\.vvenv\.alice_dictation/$APP_ID/g" "$GRADLE"
perl -0pi -e "s/com\.vvenv\.alice_dictation/$APP_ID/g" \
  android/app/src/main/AndroidManifest.xml 2>/dev/null || true

step "Android: MainActivity 包名 → $APP_ID"
# 光改 gradle 的 namespace 不够。manifest 里写的是相对类名 .MainActivity，
# 按 namespace 解析成 com.vvenv.alice.MainActivity，而 flutter create 把类生成
# 在 com.vvenv.alice_dictation 下 —— 两边对不上。编译期没人管，R8 还会因为
# 没有 keep 规则指向真实类而把它连同 FlutterActivity 一起删掉，于是 release
# 包一启动就 ClassNotFoundException 闪退。Kotlin 的包名和目录必须一起搬。
KOTLIN_ROOT="android/app/src/main/kotlin"
OLD_PKG_DIR="$KOTLIN_ROOT/$(echo "$APP_ID" | tr . /)_dictation"
NEW_PKG_DIR="$KOTLIN_ROOT/$(echo "$APP_ID" | tr . /)"
if [ -f "$OLD_PKG_DIR/MainActivity.kt" ]; then
  mkdir -p "$NEW_PKG_DIR"
  mv "$OLD_PKG_DIR/MainActivity.kt" "$NEW_PKG_DIR/MainActivity.kt"
  rmdir "$OLD_PKG_DIR" 2>/dev/null || true
fi
[ -f "$NEW_PKG_DIR/MainActivity.kt" ] || error "找不到 MainActivity.kt"
perl -0pi -e "s/^package .*\$/package $APP_ID/m" "$NEW_PKG_DIR/MainActivity.kt"

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

# url_launcher 在 Android 11+ 需要这条 package visibility 声明，
# 否则设置页的「反馈」打不开浏览器。flutter create 只写 PROCESS_TEXT 那条。
if 'android:scheme="https"' not in src:
    view_intent = (
        "    <queries>\n"
        "        <intent>\n"
        '            <action android:name="android.intent.action.VIEW"/>\n'
        '            <data android:scheme="https"/>\n'
        "        </intent>\n"
        "    </queries>\n"
    )
    if "<queries>" in src:
        src = src.replace(
            "    </queries>",
            "        <intent>\n"
            '            <action android:name="android.intent.action.VIEW"/>\n'
            '            <data android:scheme="https"/>\n'
            "        </intent>\n"
            "    </queries>",
            1,
        )
    else:
        src = src.replace("</manifest>", view_intent + "</manifest>", 1)

# Android 7.1 的圆形图标槽位。flutter create 不写这一条。
if "android:roundIcon" not in src:
    src = src.replace(
        'android:icon="@mipmap/ic_launcher"',
        'android:icon="@mipmap/ic_launcher"\n'
        '        android:roundIcon="@mipmap/ic_launcher_round"',
        1,
    )

open(path, "w", encoding="utf-8").write(src)
print(f"  权限补齐: {missing or '（已齐全）'}")
PY

step "Android: 清掉 Flutter 默认图标"
# 真正的图标是 scripts/gen-icons.py 生成、提交在仓库里的 ic_launcher.webp。
# flutter create 会把自己那套蓝色 F 的 ic_launcher.png 重新铺进同一批 mipmap
# 目录 —— 同名不同扩展名，AGP 会报 duplicate resource，不删就编不过。
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  rm -f "android/app/src/main/res/mipmap-$d/ic_launcher.png"
  [ -f "android/app/src/main/res/mipmap-$d/ic_launcher.webp" ] || \
    error "缺 mipmap-$d/ic_launcher.webp，跑一次 python3 scripts/gen-icons.py"
done

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

# --- 收尾自检 --------------------------------------------------------------

# manifest 声明的启动 Activity 必须真的存在。这一条错了在编译期毫无征兆，
# 只有真机启动时闪退，所以在这里挡住。
step "自检：manifest 的启动 Activity 与 Kotlin 源码对得上"
python3 - "$MANIFEST" "$APP_ID" "$KOTLIN_ROOT" <<'PY'
import os
import re
import sys

manifest, app_id, kotlin_root = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(manifest, encoding="utf-8").read()

m = re.search(r'<activity[^>]*android:name="([^"]+)"', src, re.S)
if not m:
    sys.exit("ERROR: manifest 里找不到 <activity>")

name = m.group(1)
fqcn = app_id + name if name.startswith(".") else name
path = os.path.join(kotlin_root, *fqcn.split(".")) + ".kt"

if not os.path.exists(path):
    sys.exit(f"ERROR: manifest 声明 {fqcn}，但 {path} 不存在 —— 装到真机上会闪退")

pkg = fqcn.rsplit(".", 1)[0]
if f"package {pkg}" not in open(path, encoding="utf-8").read():
    sys.exit(f"ERROR: {path} 的 package 声明不是 {pkg}")

print(f"  {fqcn} ✓")
PY

step "完成。接下来："
echo "  flutter analyze"
echo "  flutter run"
