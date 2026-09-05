import 'package:alice_dictation/screens/home_screen.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/services/storage.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:alice_dictation/widgets/app_button.dart';
import 'package:alice_dictation/widgets/app_icons.dart';
import 'package:alice_dictation/widgets/word_input_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 拍照识词按钮浮在单词卡片上：默认停右下角、可以拖，且不压住卡片里的东西。
///
/// 之前它挂在整个区域上、编辑模式还硬编码了一个 40 去躲「示例 / 清空」那一行；
/// 展示模式下列表滚到底时，最后一词的删除按钮正好被按钮盖住，永远点不到。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double cameraSize = 56;
  const double margin = 12; // Spacing.md，按钮离卡片四边的留白
  const Size cardSize = Size(360, 400);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  Widget wrap(Widget child, {double keyboardInset = 0}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => OcrQuotaController()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          // TextField 要一个 Material 祖先。
          child: Material(child: child),
        ),
      ),
    );
  }

  Finder cameraButton() => find.byWidgetPredicate(
        (w) => w is AppIconButton && w.semanticLabel == '拍照识词',
      );

  Finder deleteButton(String word) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '删除 $word',
      );

  /// 一张固定尺寸的单词卡片，带一颗可拖的拍照按钮。
  ///
  /// [onMoved] 传 null 时按钮不可拖（对应上层没接落点回调的情况）。
  Widget section({
    required String value,
    required bool displayMode,
    Alignment alignment = Alignment.bottomRight,
    ValueChanged<Alignment>? onMoved,
    VoidCallback? onPressed,
  }) {
    return Center(
      child: SizedBox(
        width: cardSize.width,
        height: cardSize.height,
        child: WordInputSection(
          value: value,
          onChanged: (_) {},
          onSetSample: () {},
          onClear: () {},
          startIndex: 0,
          onStartIndexChanged: (_) {},
          isDisplayMode: displayMode,
          overlayActionSize: cameraSize,
          overlayAlignment: alignment,
          onOverlayAlignmentChanged: onMoved,
          overlayAction: AppIconButton(
            icon: AppIcons.camera,
            size: cameraSize,
            variant: IconButtonVariant.gold,
            onPressed: onPressed ?? () {},
            semanticLabel: '拍照识词',
          ),
        ),
      ),
    );
  }

  /// 把按钮拖走。先走一小段跨过手势 slop，再走真正要量的那一段。
  Future<void> dragCamera(WidgetTester tester, Offset by) async {
    final gesture = await tester.startGesture(tester.getCenter(cameraButton()));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await gesture.moveBy(by);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  // Prefs 缓存了 SharedPreferences 单例，setMockInitialValues 只在第一次生效，
  // 所以清状态要经 Prefs 自己走。
  const String posKey = 'alice_camera_button_pos';

  setUp(() async {
    // 每个用例都从「没拖过」的干净状态开始。
    await Prefs.remove(posKey);
  });

  group('默认位置', () {
    testWidgets('离卡片右边和下边一样远', (tester) async {
      await tester.pumpWidget(wrap(
        section(value: 'apple\nbanana', displayMode: true),
      ));
      await tester.pumpAndSettle();

      // 展示模式下卡片就是整个 SizedBox（下面没有「示例 / 清空」那一行）。
      final card = tester.getRect(find.byType(WordInputSection));
      final camera = tester.getRect(cameraButton());

      expect(card.right - camera.right, closeTo(margin, 0.01));
      expect(card.bottom - camera.bottom, closeTo(margin, 0.01));
    });
  });

  group('不挡住卡片里的东西', () {
    testWidgets('展示模式滚到底：不压住最后一词的删除', (tester) async {
      final words = List.generate(40, (i) => 'word$i').join('\n');
      await tester.pumpWidget(wrap(section(value: words, displayMode: true)));
      await tester.pumpAndSettle();

      // 滚到底 —— 出问题的正是这一刻，最后一行停在卡片下沿。
      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      final camera = tester.getRect(cameraButton());
      final lastDelete = tester.getRect(deleteButton('word39'));

      expect(
        camera.overlaps(lastDelete),
        isFalse,
        reason: '最后一词的删除按钮 $lastDelete 被拍照按钮 $camera 盖住了',
      );
    });

    testWidgets('编辑模式：不压住「示例 / 清空」那一行', (tester) async {
      await tester.pumpWidget(wrap(
        section(value: 'apple\nbanana', displayMode: false),
      ));
      await tester.pumpAndSettle();

      final camera = tester.getRect(cameraButton());
      for (final label in ['示例', '清空']) {
        expect(
          camera.overlaps(tester.getRect(find.text(label))),
          isFalse,
          reason: '「$label」被拍照按钮盖住了',
        );
      }
    });

    testWidgets('按钮拖到上面之后，列表底部不再留空白', (tester) async {
      final words = List.generate(40, (i) => 'word$i').join('\n');

      double bottomGapAt(Alignment alignment) {
        // 列表让出的底部空间 = 最后一词的下边到卡片下边的距离。
        final card = tester.getRect(find.byType(WordInputSection));
        return card.bottom - tester.getRect(deleteButton('word39')).bottom;
      }

      for (final probe in <(Alignment, String)>[
        (Alignment.bottomRight, '停在底部时要让位'),
        (Alignment.topRight, '拖到顶部后不该继续留白'),
      ]) {
        await tester.pumpWidget(wrap(
          section(value: words, displayMode: true, alignment: probe.$1),
        ));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -4000));
        await tester.pumpAndSettle();

        final gap = bottomGapAt(probe.$1);
        if (probe.$1 == Alignment.bottomRight) {
          expect(gap, greaterThanOrEqualTo(cameraSize), reason: probe.$2);
        } else {
          expect(gap, lessThan(cameraSize), reason: probe.$2);
        }
      }
    });
  });

  group('拖拽', () {
    testWidgets('跟着手指走，并把落点报给上层', (tester) async {
      Alignment alignment = Alignment.bottomRight;
      final moved = <Alignment>[];

      await tester.pumpWidget(wrap(
        StatefulBuilder(
          builder: (context, setState) => section(
            value: 'apple\nbanana',
            displayMode: true,
            alignment: alignment,
            onMoved: (a) {
              moved.add(a);
              setState(() => alignment = a);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final before = tester.getRect(cameraButton());
      await dragCamera(tester, const Offset(-140, -140));
      final after = tester.getRect(cameraButton());

      expect(after.left - before.left, closeTo(-140, 2));
      expect(after.top - before.top, closeTo(-140, 2));

      // 一次拖动只回报一次 —— 上层照这个落点写存储。
      expect(moved, hasLength(1));
      expect(alignment, isNot(Alignment.bottomRight));
    });

    testWidgets('拖过头会停在卡片边上，不会跑出去', (tester) async {
      Alignment alignment = Alignment.bottomRight;

      await tester.pumpWidget(wrap(
        StatefulBuilder(
          builder: (context, setState) => section(
            value: 'apple\nbanana',
            displayMode: true,
            alignment: alignment,
            onMoved: (a) => setState(() => alignment = a),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await dragCamera(tester, const Offset(-2000, -2000));

      final card = tester.getRect(find.byType(WordInputSection));
      final camera = tester.getRect(cameraButton());

      expect(camera.left - card.left, closeTo(margin, 0.01));
      expect(camera.top - card.top, closeTo(margin, 0.01));
      expect(alignment, Alignment.topLeft);
    });

    testWidgets('加了拖拽之后，单击照旧能按下去', (tester) async {
      var taps = 0;

      await tester.pumpWidget(wrap(
        section(
          value: 'apple\nbanana',
          displayMode: true,
          onMoved: (_) {},
          onPressed: () => taps++,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(cameraButton());
      await tester.pumpAndSettle();

      expect(taps, 1, reason: '拖拽的 pan 识别器把单击吃掉了');
    });

    testWidgets('没接落点回调时按钮拖不动', (tester) async {
      await tester.pumpWidget(wrap(
        section(value: 'apple\nbanana', displayMode: true),
      ));
      await tester.pumpAndSettle();

      final before = tester.getRect(cameraButton());
      await dragCamera(tester, const Offset(-140, -140));

      expect(tester.getRect(cameraButton()), before);
    });
  });

  group('落点持久化', () {
    test('存进去再读出来还是同一个位置', () async {
      expect(await loadCameraButtonAlignment(), kDefaultCameraButtonAlignment);

      await saveCameraButtonAlignment(const Alignment(-0.25, 0.5));
      expect(await loadCameraButtonAlignment(), const Alignment(-0.25, 0.5));
    });

    test('存坏了就回默认的右下角', () async {
      await Prefs.setString(posKey, '你好');
      expect(await loadCameraButtonAlignment(), kDefaultCameraButtonAlignment);
    });

    test('越界的值会夹回 -1 ~ 1', () async {
      // y 轴 +1 是下边，所以 (-9, 42) 夹完是左下角。
      await Prefs.setString(posKey, '-9,42');
      expect(await loadCameraButtonAlignment(), Alignment.bottomLeft);
    });
  });

  testWidgets('首页：键盘弹起时拍照按钮仍在', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HomeScreen(), keyboardInset: 300));
    await tester.pumpAndSettle();

    expect(cameraButton(), findsOneWidget);
  });
}
