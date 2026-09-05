# 从 Expo / React Native 迁到 Flutter

0.6.3 之前，Alice 听写是 Expo (React Native) 应用。Flutter 版把它整个重写了一遍，
行为对齐之后原实现从仓库里删除。**最后一个包含 RN 代码的提交打了 tag
`rn-final`** —— 要看历史实现从那里 checkout：

```bash
git show rn-final:src/lib/dictation.ts
git checkout rn-final -- src/          # 只取出来看，别提交
```

这份文档留着两张对照表和几条踩过的坑，用途是回答「这个依赖 / 这段代码当初为什么
是这样」，不是使用文档。

`lib/` 和 `pubspec.yaml` 里还留着不少「对应 RN 版 `src/lib/xxx.ts`」这样的注释。
它们是**故意留下的**：Dart 侧为什么这么写，答案往往就在那份实现里，而
`test/golden/rn_golden.json` 至今仍在按它的行为做断言。路径按 `rn-final` 解析，
下面的目录对照表也能查。

## 行为是怎么对齐的

`test/rn_equivalence_test.dart` 断言的期望值不是手写的，是**真的跑 Expo 版的
TypeScript** 跑出来的：`src/lib/dictation.ts`、`dictionary.ts` 的全部导出函数，
加上 `ocr.ts` 里的 `extractWordsFromOcrText`，共 198 个用例，语料落在
`test/golden/rn_golden.json`。

生成器 `scripts/rn-golden/generate.sh` 保留着，但它不再读工作区 —— Expo 代码
在这个分支上已经没有了 —— 而是从 git ref 取源码：

```bash
bash scripts/rn-golden/generate.sh            # 对齐 main
bash scripts/rn-golden/generate.sh rn-final   # 对齐迁移那一刻的实现
```

这就是「从 main 同步」的验证手段：先按 main 重新生成语料，Dart 测试会精确地在
「main 修了、这边还没移植」的地方红，红的地方就是移植清单。

**等 main 上的 Expo 代码也没了，这个脚本就跑不动了。** 到那时语料变成一份冻结的
行为基线：仍然拦得住 Dart 侧漂移，但不能再生成，把 `scripts/rn-golden/` 删掉即可。

## 目录对照

| RN (`src/`) | Flutter (`lib/`) |
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
| `@expo/vector-icons` | Material Icons（映射表在 `lib/widgets/app_icons.dart`） |
| `@react-navigation/*` | `Navigator` + `MaterialPageRoute` |
| `expo-constants`（版本号） | `package_info_plus` |
| React Context | `provider` |

## 老数据迁移

**这是包名不能改的唯一原因。** 手机上装着的老版本包名是 `com.vvenv.alice`，
Flutter 版沿用它才算同一个 app 的升级，才读得到老沙箱里的数据。

`lib/services/legacy_migration_io.dart` 在首次启动时把 AsyncStorage 的数据搬进
`shared_preferences`：

- **Android** —— app 私有目录里的 SQLite 库 `RKStorage`，表
  `catalystLocalStorage(key TEXT PRIMARY KEY, value TEXT)`。
- **iOS** —— `Documents/RCTAsyncLocalStorage_V1/manifest.json` 存小值；大值在
  manifest 里是 `null`，实际内容放在以 key 的 MD5 命名的同目录文件里。

只跑一次、不覆盖 Flutter 版自己写过的新值、失败不阻塞启动（全新安装读不到任何
东西是正常情况）。两版的 key 逐字一致（`dictation_*` / `alice_*`）。

## 迁移期修过的几个坑

- **Web 构建**：`dart:io` 从 `tts.dart` 里移出去，改成按平台条件导入
  （`tts_cache.dart` → `tts_cache_io.dart` / `tts_cache_noop.dart`）。Web 上磁盘
  缓存是空实现，发音直接走系统 TTS —— 与 RN 版 Web 的行为一致。
- **音频会话**：`audio_session` 对应 RN 版 `setAudioModeAsync` 的静音键仍出声 /
  后台播放 / 不混音。
- **真机闪退**：manifest 的 `.MainActivity` 按 gradle namespace 解析成
  `com.vvenv.alice.MainActivity`，而 `flutter create --project-name
  alice_dictation` 把类生成在 `com.vvenv.alice_dictation` 下。编译期毫无征兆，
  R8 还把这个「没人引用」的类连同 `FlutterActivity` 一起删了 —— 0.6.2 的
  `classes.dex` 只有 354 KB，一个 `com/vvenv/*` 都不剩。详见 README「出包自检」。
- **应用图标**：`flutter create` 铺的是 Flutter 自带的蓝色 F。
  `scripts/gen-icons.py` 从 `assets/icons/` 重新生成整套，规则沿用 expo prebuild
  当年那一套，图标与老版本逐像素一致。
- **版本号**：Flutter 只认 `pubspec.yaml` 的 `version: x.y.z+code`。它一度不在
  版本同步脚本的范围里，停在 `0.6.2+1` —— versionCode 1 比老版本的 10 还低，
  覆盖安装会被系统按降级拒掉，而卸载重装正好会毁掉上面那套老数据迁移要读的东西。
- **Web 上的中文字体**：见 README「环境相关的坑」第 4 条。

## 体积

|            | APK   |
| ---------- | ----- |
| Expo 版    | 109 MB |
| Flutter 版 | 72.8 MB |
