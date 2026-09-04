# Alice 听写 · Flutter 版

从 `../src`（Expo / React Native）迁移过来的 Flutter 实现。

## 当前状态

代码迁移完成并已验证：

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | 干净，0 issue |
| `flutter test` | 18/18 通过（含 114 个 RN 等价性用例） |
| `flutter build web --release` | ✅ 成功 |
| `flutter build apk --release` | ⚠️ 未完成 —— 卡在本机网络，见下 |

```bash
cd flutter_app
bash scripts/bootstrap.sh   # flutter create + pub get + 平台配置（幂等）
flutter analyze
flutter test
flutter run
```

### APK 为什么没构建出来

不是代码问题，是这台机器的网络：到 Maven / dl.google.com 的连接会「建立成功但零字节」地挂死
（同一批包用 curl 走 maven.aliyun.com 有 1.9 MB/s，走 repo.maven.apache.org 只有 17 KB/s）。
Gradle 的依赖解析因此停在半路，多次重试都停在不同的包上。

已经做的缓解（都在仓库里）：

- `android/build.gradle.kts` / `android/settings.gradle.kts`：阿里云镜像优先，官方源兜底
- `android/gradle.properties`：显式 HTTP 连接/读取超时，让挂死的连接快速失败重试
- `android/app/build.gradle.kts` + 根 `build.gradle.kts`：NDK 钉到本机已装的 27.1.12297006
  （`flutter.ndkVersion` 指向的 28.2.13676358 在本机是个残缺空目录，会触发反复重下 1GB）

还需要在 Flutter SDK 里做一处改动（**不在本仓库内**），已改并留了备份：

```
/opt/homebrew/share/flutter/packages/flutter_tools/gradle/settings.gradle.kts
# 还原：cp settings.gradle.kts.orig settings.gradle.kts
```

Flutter 自带的 gradle composite build 把仓库硬写成 `google()` + `mavenCentral()`，
并设了 `FAIL_ON_PROJECT_REPOS`，项目侧覆盖不了，只能改 SDK 里这个文件。

**在网络正常的环境下（或换个代理节点）重跑 `flutter build apk --release` 即可。**
Gradle 缓存是增量的，之前几轮已经拉下来不少依赖，重跑不会从零开始。

## 目录对照

| RN (`../src`) | Flutter (`lib`) |
| --- | --- |
| `lib/theme.tsx` + `lib/designTokens.ts` | `theme/app_colors.dart`、`theme/tokens.dart`、`theme/theme_controller.dart` |
| `lib/storage.ts` | `services/storage.dart` + `services/prefs.dart` |
| `lib/library.ts`（16k 行代码即数据） | `assets/data/library.json` + `services/library_data.dart` |
| `lib/dictionary.ts` + `lib/ecdict-meta.json` | `services/dictionary.dart` + `assets/data/ecdict-meta.json` |
| `lib/dictation.ts` | `services/dictation.dart` |
| `lib/tts.ts` | `services/tts.dart` |
| `lib/sound.ts` | `services/sound.dart` |
| `lib/haptics.ts` | `services/haptics.dart` |
| `lib/credits.ts` | `services/credits.dart` |
| `lib/ocrConfig.ts` | `services/ocr_config.dart` |
| `lib/ocr.ts` | `services/ocr.dart` |
| `components/OcrSection.tsx` | `services/ocr_runner.dart`（RN 侧是个不渲染的 ref 组件，这里做成普通类） |
| `hooks/usePlayback.ts` | `state/playback_controller.dart` |
| `hooks/useToast.ts` | `state/toast_controller.dart` |
| `hooks/useWrongWords.ts` | `state/wrong_words_controller.dart` |
| `hooks/useOcrQuota.ts` | `state/ocr_quota_controller.dart` |
| `components/*.tsx` | `widgets/*.dart` |
| `screens/*.tsx` | `screens/*.dart` |
| `App.tsx` | `main.dart` |

## 依赖对照

| Expo | Flutter |
| --- | --- |
| `@react-native-async-storage/async-storage` | `shared_preferences` |
| `expo-speech` | `flutter_tts` |
| `expo-audio` | `just_audio` + `audio_session` |
| `expo-image-picker` | `image_picker` |
| `expo-image-manipulator` | `flutter_image_compress` |
| `expo-file-system` | `path_provider` + `dart:io`（按平台条件导入） |
| `expo-haptics` | `flutter/services` 的 `HapticFeedback` |
| `expo-clipboard` | `flutter/services` 的 `Clipboard` |
| `expo-linear-gradient` | `LinearGradient`（内置） |
| `react-native-svg`（倒计时环） | `CustomPainter`（内置） |
| `@expo/vector-icons` | Material Icons（映射表在 `widgets/app_icons.dart`） |
| `@react-navigation/*` | `Navigator` + `MaterialPageRoute` |
| `expo-constants`（版本号） | `package_info_plus` |
| React Context | `provider` |

## 已知缺口

按重要性排序。

### 1. 全部未经编译验证 ⚠️

Flutter SDK 还在下载，`flutter analyze` 一次都没跑过。这是目前唯一的大风险 ——
代码是照 Dart 语义写的，但没过编译器的东西不能算能跑。

### 2. TTS 语速需要真机校准

`services/tts.dart` 的 `_normalizedRate()` 把用户的 0.5–1.5 区间映射到各平台：
iOS 走 `AVSpeechUtterance` 的 0..1，Android 走 `TextToSpeech.setSpeechRate` 的
1.0 = 正常。这组映射是按文档推的，没在真机上听过。

### 3. 包名不能改

`scripts/bootstrap.sh` 会把 applicationId / bundleIdentifier 固定成
`com.vvenv.alice`，和 RN 版一致。**改了包名就是另一个沙箱**，下面的老数据迁移
会读不到任何东西，老用户的错词本 / 历史 / 收藏 / Credits 全部丢失。

### 4. 发版流程要重搭

RN 版靠 `eas build` + `scripts/release.sh` 管证书和云端构建，Flutter 侧没有
等价物，签名与 CI 需要重做。

## 已解决

- **Web 构建**：`dart:io` 已从 `tts.dart` 移出，改成按平台条件导入
  （`tts_cache.dart` → `tts_cache_io.dart` / `tts_cache_noop.dart`）。
  Web 上磁盘缓存为空实现，发音直接走系统 TTS —— 与 RN 版 web 的行为一致。
- **老数据迁移**：`services/legacy_migration_io.dart` 在首次启动时把 RN 版
  AsyncStorage 的数据搬进 shared_preferences。Android 读私有目录里的 SQLite
  库 `RKStorage`（表 `catalystLocalStorage`），iOS 读
  `Documents/RCTAsyncLocalStorage_V1/manifest.json`（大值在以 key 的 MD5
  命名的独立文件里）。只跑一次、不覆盖新值、失败不阻塞启动。
- **音频会话**：`audio_session` 已接入，对应 RN 版 `setAudioModeAsync` 的
  静音键仍出声 / 后台播放 / 不混音。
- **平台配置**：`scripts/bootstrap.sh` 生成平台目录并写入权限、用途说明、
  后台音频、应用名与包名。

## 资源

`assets/data/library.json` 由 `../scripts/export-library-json.mjs` 从
`../src/lib/library.ts` 导出（290 条词表）。RN 侧的词库变了之后重新跑一遍：

```bash
node scripts/export-library-json.mjs
```

`assets/data/ecdict-meta.json` 直接复制自 `../src/lib/ecdict-meta.json`，
上游由 `pnpm dict:build` 生成。

## 配置

OCR 密钥走编译期常量，不进仓库：

```bash
flutter build apk --dart-define=ZHIPU_API_KEY=xxx
```

Web 构建**不要**传这个参数 —— Web 产物是公开的，用户需自备 API Key
（与 RN 版 `app.config.js` 里 `isWebBuild` 的处理一致）。
