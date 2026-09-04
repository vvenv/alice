import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/dictionary.dart';
import 'services/legacy_migration.dart';
import 'services/library_data.dart';
import 'services/prefs.dart';
import 'services/storage.dart';
import 'services/tts.dart';
import 'state/ocr_quota_controller.dart';
import 'theme/theme_controller.dart';
import 'screens/home_screen.dart';

/// 入口。对应 RN 版 App.tsx。
///
/// RN 侧靠 expo-font + expo-splash-screen 在字体加载完成前挡住首帧；
/// Flutter 的 assets 字体是打包进产物的，不需要异步加载，所以启动流程
/// 只剩下「读一次存储 + 解析词典/词库资源」。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Prefs.init();

  // 从 RN 版 AsyncStorage 搬运老数据（错词本、历史、收藏、Credits…）。
  // 只在首次启动时真正做事，失败不阻塞启动。
  await migrateLegacyAsyncStorage();

  await Future.wait([
    loadDictionary(),
    loadLibrary(),
  ]);

  // 语速要在第一次朗读之前灌进 TTS 引擎。
  setSpeechRate(await loadSpeechRate());

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
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
