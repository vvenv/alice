import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alice_dictation/screens/image_edit_screen.dart';
import 'package:alice_dictation/services/image_edit.dart';
import 'package:alice_dictation/services/ocr.dart' show XFile;
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('裁切框', () {
    test('铺满整张图算没裁', () {
      expect(isIdentityCrop(const Rect.fromLTWH(0, 0, 1, 1)), isTrue);
      expect(isIdentityCrop(const Rect.fromLTWH(0.1, 0, 0.9, 1)), isFalse);
    });

    test('没旋转也没裁就是原图', () {
      expect(const ImageEditTransform().isIdentity, isTrue);
      expect(
        const ImageEditTransform(quarterTurns: 1).isIdentity,
        isFalse,
      );
    });

    test('旋转奇数次会把宽高对调', () {
      expect(rotatedImageSize(4, 2, 0), const Size(4, 2));
      expect(rotatedImageSize(4, 2, 1), const Size(2, 4));
      expect(rotatedImageSize(4, 2, 2), const Size(4, 2));
      expect(rotatedImageSize(4, 2, 3), const Size(2, 4));
    });

    test('裁切框不会超出 0–1，也不会缩得看不见', () {
      final clamped = clampNormalizedCrop(
        const Rect.fromLTRB(-0.2, 0.9, 0.05, 1.4),
        minSize: 0.2,
      );
      expect(clamped.left, greaterThanOrEqualTo(0));
      expect(clamped.top, greaterThanOrEqualTo(0));
      expect(clamped.right, lessThanOrEqualTo(1));
      expect(clamped.bottom, lessThanOrEqualTo(1));
      expect(clamped.width, greaterThanOrEqualTo(0.2 - 1e-6));
      expect(clamped.height, greaterThanOrEqualTo(0.2 - 1e-6));
    });
  });

  group('导出像素', () {
    testWidgets('裁左半边只留下红色', (tester) async {
      await tester.runAsync(() async {
        final source = await _twoToneImage();
        final cropped = await renderEditedImage(
          source: source,
          transform: const ImageEditTransform(
            crop: Rect.fromLTWH(0, 0, 0.5, 1),
          ),
        );
        expect(cropped.width, 2);
        expect(cropped.height, 2);
        expect(await _rgb(cropped, 0, 0), (255, 0, 0));
        expect(await _rgb(cropped, 1, 1), (255, 0, 0));
        cropped.dispose();
        source.dispose();
      });
    });

    testWidgets('顺时针 90° 后宽高对调，左上角仍是红', (tester) async {
      await tester.runAsync(() async {
        final source = await _twoToneImage();
        final rotated = await renderEditedImage(
          source: source,
          transform: const ImageEditTransform(quarterTurns: 1),
        );
        expect(rotated.width, 2);
        expect(rotated.height, 4);
        // 原图 (0,1) 红 → 90° 后到 (0,0)
        expect(await _rgb(rotated, 0, 0), (255, 0, 0));
        // 原图 (3,0) 蓝 → 90° 后到 (1,3)
        expect(await _rgb(rotated, 1, 3), (0, 0, 255));
        rotated.dispose();
        source.dispose();
      });
    });
  });

  group('编辑页', () {
    testWidgets('取消不交图', (tester) async {
      final file = _tinyPngFile();
      final image = (await tester.runAsync(_twoToneImage))!;
      XFile? result = XFile('sentinel');

      await tester.pumpWidget(_wrap(const SizedBox()));
      final future = tester.state<NavigatorState>(find.byType(Navigator)).push<XFile>(
        MaterialPageRoute(
          builder: (_) => ImageEditScreen(file: file, decodedImage: image),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('调整图片'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      result = await future;
      expect(result, isNull);
    });

    testWidgets('不改就完成，交回原图', (tester) async {
      final file = _tinyPngFile();
      final image = (await tester.runAsync(_twoToneImage))!;

      await tester.pumpWidget(_wrap(const SizedBox()));
      final future = tester.state<NavigatorState>(find.byType(Navigator)).push<XFile>(
        MaterialPageRoute(
          builder: (_) => ImageEditScreen(file: file, decodedImage: image),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(identical(await future, file), isTrue);
    });

    testWidgets('旋转后再完成，交出去的是新图', (tester) async {
      final file = _tinyPngFile();
      final image = (await tester.runAsync(_twoToneImage))!;

      await tester.pumpWidget(_wrap(const SizedBox()));
      final future = tester.state<NavigatorState>(find.byType(Navigator)).push<XFile>(
        MaterialPageRoute(
          builder: (_) => ImageEditScreen(file: file, decodedImage: image),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('向右旋转'));
      await tester.pump();
      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      final result = await future;
      expect(result, isNotNull);
      expect(identical(result, file), isFalse);
      final bytes = await result!.readAsBytes();
      expect(bytes, isNotEmpty);
    });
  });
}

const Color _red = Color(0xFFFF0000);
const Color _blue = Color(0xFF0000FF);

Widget _wrap(Widget home) {
  return ChangeNotifierProvider(
    create: (_) => ThemeController(),
    child: MaterialApp(home: Scaffold(body: home)),
  );
}

/// 4×2：左红右蓝。
Future<ui.Image> _twoToneImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()..color = _red,
  );
  canvas.drawRect(
    const Rect.fromLTWH(2, 0, 2, 2),
    Paint()..color = _blue,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(4, 2);
  } finally {
    picture.dispose();
  }
}

Future<(int, int, int)> _rgb(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  final bytes = data!.buffer.asUint8List();
  return (bytes[offset], bytes[offset + 1], bytes[offset + 2]);
}

/// 1×1 红 PNG，避免测试里再走一遍 `toImage`。
XFile _tinyPngFile() {
  return xFileFromPngBytes(
    Uint8List.fromList(const <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]),
    name: 'tiny.png',
  );
}
