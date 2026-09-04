# Alice 听写 · Flutter 版

从 `../src`（Expo / React Native）迁移过来的 Flutter 实现。

## 当前状态

**代码已完成，尚未编译验证。** 迁移是在本机还没装 Flutter SDK 的情况下写的
（`brew install --cask flutter` 正在后台下载），所以下面这几步还没跑过：

```bash
cd flutter_app
flutter create .          # 生成 android/ ios/ web/ macos/ 平台目录
flutter pub get
flutter analyze           # 预期会有需要修的静态错误
dart format .
flutter run
```

`flutter create .` 会在保留现有 `lib/`、`assets/`、`pubspec.yaml` 的前提下补出
平台目录。补完之后还要手工做的事见下面「平台配置」。

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
| `expo-audio` | `just_audio` |
| `expo-image-picker` | `image_picker` |
| `expo-image-manipulator` | `flutter_image_compress` |
| `expo-file-system` | `path_provider` + `dart:io` |
| `expo-haptics` | `flutter/services` 的 `HapticFeedback` |
| `expo-clipboard` | `flutter/services` 的 `Clipboard` |
| `expo-linear-gradient` | `LinearGradient`（内置） |
| `react-native-svg`（倒计时环） | `CustomPainter`（内置） |
| `@expo/vector-icons` | Material Icons（映射表在 `widgets/app_icons.dart`） |
| `@react-navigation/*` | `Navigator` + `MaterialPageRoute` |
| `expo-constants`（版本号） | `package_info_plus` |
| React Context | `provider` |

## 已知缺口

按重要性排序，这些是**还没解决**的问题，不是「稍后优化」：

### 1. Web 端跑不起来

`services/tts.dart` 直接 import 了 `dart:io`（`File` / `Directory` / `Platform`），
`flutter build web` 会直接编译失败。RN 版通过 `Platform.OS !== "web"` 在运行时
关掉磁盘缓存，Dart 需要在编译期解决。

修法：把文件缓存抽成条件导入 —— `file_cache_stub.dart` / `file_cache_io.dart` /
`file_cache_web.dart`，`tts.dart` 用
`import 'file_cache_stub.dart' if (dart.library.io) 'file_cache_io.dart';`。

在这之前 Flutter 版只能出 Android / iOS。这正是迁移前评估里说的那条代价。

### 2. 老用户数据不会自动迁移

存储 key 与 RN 版逐字一致（`dictation_wrong_words`、`alice_ocr_credits` …），
但 **AsyncStorage 和 shared_preferences 是两套底层存储**：

- Android：AsyncStorage → SQLite `RKStorage`；shared_preferences → `SharedPreferences` XML
- iOS：AsyncStorage → `RCTAsyncLocalStorage_V1` 目录；shared_preferences → `NSUserDefaults`

同一台设备上升级到 Flutter 版，用户的错词本、历史记录、收藏、Credits 余额
**会全部丢失**。上线前必须写一次性迁移（原生侧读旧存储 → 写进
shared_preferences），或者接受这次数据断层并提前公告。

### 3. TTS 语速需要真机校准

`services/tts.dart` 的 `_normalizedRate()` 把用户的 0.5–1.5 区间映射到各平台：
iOS 走 `AVSpeechUtterance` 的 0..1，Android 走 `TextToSpeech.setSpeechRate` 的
1.0 = 正常。这组映射是按文档推的，没在真机上听过，需要实测调整。

### 4. 平台配置还没做

`flutter create .` 之后需要补：

- **Android**：`AndroidManifest.xml` 加 `CAMERA`、`INTERNET` 权限；应用名、包名、
  图标（`assets/images/icon.png`）、启动图
- **iOS**：`Info.plist` 加 `NSCameraUsageDescription`、`NSPhotoLibraryUsageDescription`；
  后台音频（RN 版 `setAudioModeAsync` 开了 `shouldPlayInBackground`）
- **签名与发版**：RN 版靠 `eas build` + `scripts/release.sh`，Flutter 侧没有等价物，
  证书和 CI 要重搭

### 5. 音频会话

RN 版 `tts.ts` 里的 `setAudioModeAsync({ playsInSilentMode: true,
shouldPlayInBackground: true, interruptionMode: "doNotMix" })` 没有对应实现。
`just_audio` 需要配合 `audio_session` 包做同样的事，目前是默认行为
（iOS 静音键按下时可能不发声）。

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
