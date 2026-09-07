import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/dictionary.dart';
import 'services/haptics.dart';
import 'services/legacy_migration.dart';
import 'services/library_data.dart';
import 'services/prefs.dart';
import 'services/sound.dart';
import 'services/storage.dart';
import 'services/tts.dart';
import 'state/ocr_quota_controller.dart';
import 'theme/theme_controller.dart';
import 'theme/tokens.dart';
import 'screens/home_screen.dart';

/// 入口。对应 RN 版 App.tsx。
///
/// RN 侧靠 expo-font + expo-splash-screen 在字体加载完成前挡住首帧；
/// Flutter 的 assets 字体是打包进产物的，不需要异步加载，所以启动流程
/// 只剩下「读一次存储 + 解析词典/词库资源」。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 铺满到系统栏之下。
  //
  // 不开这个，Android 会把窗口内缩到系统栏之上，MediaQuery.padding.bottom
  // 就是 0 —— SafeArea 什么也撑不开，底部内容会紧贴导航栏/手势条。
  // （RN 的 react-native-safe-area-context 两种模式下都报得出 inset，
  // Flutter 的 SafeArea 只认 MediaQuery，所以这一句是必须的。）
  // AnnotatedRegion 里那套 SystemUiOverlayStyle 也要靠它才有意义。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await Prefs.init();

  // 从 RN 版 AsyncStorage 搬运老数据（错词本、历史、收藏、Credits…）。
  // 只在首次启动时真正做事，失败不阻塞启动。
  await migrateLegacyAsyncStorage();

  // 词库小，挡住首帧没问题。词典 JSON 约 3.3MB，Web 上按需 fetch+解析，
  // 不该卡住第一屏；首页 / 开始听写会在需要时 await loadDictionary()。
  await loadLibrary();
  unawaited(loadDictionary());

  // 语速要在第一次朗读之前灌进 TTS 引擎。
  setSpeechRate(await loadSpeechRate());

  // 提示音 / 触感的开关也要在这里读回来。以前只有设置页读，于是关掉提示音
  // 之后重启，在用户再次打开设置页之前又会响。
  await loadSoundEnabled();
  await Haptics.load();

  // 系统 TTS 引擎是异步初始化的，第一次朗读撞上这个窗口会被整段吃掉
  // （见 tts.dart 的 _getTts）。启动就把它拉起来，但不等它 —— 预热失败
  // 不该挡住首帧。
  unawaited(warmUpTts());

  runApp(const AliceApp());
}

class AliceApp extends StatelessWidget {
  const AliceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => OcrQuotaController()),
      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  bool _themeLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    await context.read<ThemeController>().load(brightness);
    if (mounted) setState(() => _themeLoaded = true);
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    // 用户没有显式选过主题时才跟随系统 —— 逻辑在 ThemeController 里。
    context.read<ThemeController>().syncSystemBrightness(
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final colors = theme.colors;

    if (!_themeLoaded) {
      // 主题定下来之前先铺一块中性底色，避免闪一下反色。
      return ColoredBox(
          color: colors.background, child: const SizedBox.expand());
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: MaterialApp(
        title: 'Alice 听写',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: theme.isDark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: colors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: colors.primary,
            brightness: theme.isDark ? Brightness.dark : Brightness.light,
          ),
          // 文字默认走系统无衬线；需要衬线/展示体的地方各自指定 fontFamily
          // （与 RN 版 designTokens.fonts 的用法一致）。
          //
          // Web 例外：CanvasKit 够不着系统字体，默认字族只有 Roboto，中文
          // 全是豆腐块。引擎本来有「缺字就去 fonts.gstatic.com 下 Noto」的
          // 兜底，但这个应用自己注册了思源宋体，缺字检查判定已覆盖，补丁
          // 字体不会下载 —— 而它又不在默认字族的兜底链里。（就算下载得到，
          // gstatic 在国内也拉不到，不能指望。）
          //
          // 所以 Web 上把打包进产物的思源宋体显式挂成兜底字族。fontFamily
          // 必须一起写死成 Roboto：fontFamilyFallback 只在 fontFamily 非空时
          // 生效，只给 fallback 不给 family 是没有效果的（实测）。
          //
          // 原生平台不加：系统字体本来就有中文，挂上兜底反而会把正文变成
          // 衬线，与 RN 版不一致。
          fontFamily: kIsWeb ? 'Roboto' : null,
          fontFamilyFallback: kIsWeb ? const [AppFonts.serif] : null,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
