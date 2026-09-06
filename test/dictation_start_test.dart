import 'package:alice_dictation/screens/dictation_screen.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 进听写必须等转场结束再自动开始。转场中途开口，iOS 会把第一句吃掉；
/// 点暂停再继续能出声，是因为那时页面已经停稳了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
  });

  Widget wrap(Widget home) {
    final theme = ThemeController()..setMode(ThemeModeSetting.dark);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider(create: (_) => OcrQuotaController()),
      ],
      child: MaterialApp(home: home),
    );
  }

  testWidgets('转场还没结束时不会自动开始，结束后才进入播放', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                PageRouteBuilder<void>(
                  transitionDuration: const Duration(milliseconds: 800),
                  pageBuilder: (_, __, ___) => const DictationScreen(
                    words: ['apple'],
                    intervalSec: 0.05,
                    autoNext: false,
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(DictationScreen), findsOneWidget);
    expect(
      find.text('继续'),
      findsOneWidget,
      reason: '转场中途不能开始，否则第一句会被 iOS 吃掉',
    );

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(
      find.text('暂停'),
      findsOneWidget,
      reason: '转场结束后应该自动开始听写',
    );
  });
}
