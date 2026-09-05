# Alice 听写 · Flutter 版

从 `../src`（Expo / React Native）迁移过来的 Flutter 实现。

## 当前状态

迁移完成，四个目标全部构建通过。

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | 干净，0 issue |
| `flutter test` | 18/18 通过（含 114 个 RN 等价性用例） |
| `flutter build web --release` | ✅ |
| `flutter build apk --release` | ✅ 72.7 MB（RN 版 109 MB，小 33%） |

```bash
cd flutter_app
bash scripts/bootstrap.sh   # flutter create + pub get + 平台配置（幂等）
flutter analyze
flutter test
flutter build apk --release --dart-define=ZHIPU_API_KEY=xxx
```

APK 校验结果：包名 `com.vvenv.alice`（与 RN 版一致，老数据迁移依赖这一点）、
应用名「Alice 听写」、版本 0.6.3（versionCode 11）、启动 Activity
`com.vvenv.alice.MainActivity` 确实在 `classes.dex` 里、`app.json` 里的六个权限
齐全，五个密度的应用图标与自适应图标都是 Alice 的怀表，词典 / 词库 / 字体 /
音效资源全部打进了 `flutter_assets`。

> 出包之后请照着上面这几项核一遍，尤其是启动 Activity —— 少了它编译期毫无
> 征兆，装到手机上必然闪退。参考命令：
>
> ```bash
> aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | head
> ```

体积构成里最大的两块是两个思源宋体（各 14.1 MB，Flutter 只对图标字体做
tree-shaking，正文字体不裁剪）和三个架构的原生库（约 50 MB）。
（比之前记的 68 MB 大了约 4.7 MB：那一版的 `classes.dex` 只有 354 KB，R8 把
MainActivity 连同大半个 Java 侧当死代码删了 —— 见下面「真机闪退」。）
按架构分包能显著减小单设备体积：

```bash
flutter build apk --release --split-per-abi   # arm64 单包约 35 MB
```

### 环境相关的坑（本机踩过，换机器不一定有）

这些与迁移代码无关，但值得记下来：

1. **Gradle 依赖拉不动**。到 Maven Central / dl.google.com 的连接会「建立成功但
   零字节」地挂死。已在 `android/build.gradle.kts`、`android/settings.gradle.kts`
   配好阿里云镜像（官方源兜底），`android/gradle.properties` 里加了 HTTP 超时
   让挂死连接快速失败重试。Flutter SDK 自带的 gradle composite build 把仓库硬写死
   且设了 `FAIL_ON_PROJECT_REPOS`，项目侧覆盖不了，只能改 SDK 里的
   `flutter_tools/gradle/settings.gradle.kts`（同目录留了 `.orig` 备份）。

2. **NDK 反复重下 1 GB**。`flutter.ndkVersion` 指向 28.2.13676358，而本机那份是
   中断下载留下的空目录，AGP 每次判定未安装。已把 ndkVersion 钉到本机完整安装的
   27.1.12297006 —— app 模块和所有插件子模块都要钉（`jni` 这类插件自己声明
   `ndkVersion flutter.ndkVersion`），根 `build.gradle.kts` 里的 hook 必须注册在
   `evaluationDependsOn(":app")` **之前**，否则抛 already evaluated。

3. **`gen_snapshot` 被 macOS 杀掉并删除**。手动 curl 下载 SDK zip 会让整个 SDK 带上
   `com.apple.quarantine`，Gatekeeper 对未签名可执行文件先 SIGKILL（表现为
   `AOT snapshotter exited with code -9`）再移除文件。解法：
   `xattr -dr com.apple.quarantine <flutter-sdk>` 然后 `flutter precache --force --android`
   把被删的产物补回来。用 `brew install --cask flutter` 正常安装不会有这问题。

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

### 1. iOS 从没跑过；Android 只验到「能启动」⚠️

Web 产物在浏览器里手动走过完整流程（首页 → 设置 → 听写 → 完成，深浅色都看
了）。Android 装到真机上过一次，第一版一启动就闪退（原因见下面「已解决」的
「真机闪退」），修完重新出包。**iOS 一次都没构建、更没装过。**

原生侧还没有人真的用过的：TTS 发音与语速、音频会话（静音键 / 后台播放）、
拍照与相册 OCR、老数据迁移。这些在 Web 上要么是空实现要么走不到。

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
- **真机闪退**：manifest 里的 `android:name=".MainActivity"` 按 gradle 的
  namespace 解析成 `com.vvenv.alice.MainActivity`，而 `flutter create --org
  com.vvenv --project-name alice_dictation` 把类生成在
  `com.vvenv.alice_dictation` 下 —— bootstrap 只改了 gradle 与 manifest 的包名，
  没搬 Kotlin 源码。编译期没有任何征兆（manifest 不校验类存不存在），R8 还因为
  没有 keep 规则指向真实类，把 MainActivity 连同 FlutterActivity 一起当死代码
  删了：`classes.dex` 里一个 `com/vvenv/*` 都不剩，装上去必然
  ClassNotFoundException。现在源码在 `com/vvenv/alice/` 下，
  `scripts/bootstrap.sh` 会一并搬包名，末尾还会核对 manifest 声明的 Activity
  在 Kotlin 源码里确实存在。
- **应用图标**：`flutter create` 铺的是 Flutter 自带的蓝色 F。
  `scripts/gen-icons.py` 从 `assets/images/` 的两张源图生成三个平台的整套图标
  （Android 五个密度的传统 / 圆形 / 自适应前景 + `mipmap-anydpi-v26` 的自适应
  XML 与 `iconBackground` 颜色、iOS 的 appiconset、Web 的 favicon 与 PWA 图标），
  与 RN 版逐像素一致。产物提交进仓库，bootstrap 只负责删掉 `flutter create`
  重新铺回来的默认 `ic_launcher.png`（和我们的 `.webp` 同名会撞 duplicate
  resource）。
- **版本号**：Flutter 的 versionName / versionCode 只认 `pubspec.yaml` 的
  `version: x.y.z+code`（`build.gradle.kts` 读的是 `flutter.versionName`）。
  它原先不在 `../scripts/lib/version.sh` 的同步范围里，一直停在 `0.6.2+1` ——
  versionCode 1 比装在机器上的 RN 版（10）还低，覆盖安装会被系统按降级拒掉。
  现在 `sync_versions()` 一并改写它，`pnpm release:android patch` 之类的命令
  会把五处版本号一起推上去。
- **Web 上的中文字体**：CanvasKit 够不着系统字体，默认字族只有 Roboto，
  中文原本全渲染成豆腐块 —— 引擎「缺字就去 fonts.gstatic.com 下 Noto」的兜底
  被应用自己注册的思源宋体骗过了，判定已覆盖便不下载，而它又不在默认字族的
  兜底链里（何况 gstatic 国内也拉不到）。`main.dart` 里 Web 分支显式
  `fontFamily: 'Roboto'` + `fontFamilyFallback: [NotoSerifSC]`；两个都要写，
  只给 fallback 不给 family 不生效。原生不加，否则正文中文会变成衬线。
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

`assets/images/icon.png`、`adaptive-icon.png` 是 RN 版 `../assets/` 的副本，
应用图标由它们生成。图标本身改了之后重新跑一遍，再把产物一起提交：

```bash
python3 scripts/gen-icons.py   # 需要 Pillow
```

## 配置

OCR 密钥走编译期常量，不进仓库：

```bash
flutter build apk --dart-define=ZHIPU_API_KEY=xxx
```

Web 构建**不要**传这个参数 —— Web 产物是公开的，用户需自备 API Key
（与 RN 版 `app.config.js` 里 `isWebBuild` 的处理一致）。
