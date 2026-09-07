import 'dart:async';

import 'package:alice_dictation/services/abort.dart';
import 'package:alice_dictation/services/ocr.dart';
import 'package:alice_dictation/services/ocr_config.dart';
import 'package:alice_dictation/services/ocr_runner.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 识别中途的出口。
///
/// 此前一个 timeout 都没有、也不能取消：网络「连上了但零字节」地挂住时，
/// 顶栏那个「识别中…」会永远转下去，只能杀掉应用。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    // 配一份 BYOK，好让预检放行、真正走到识别那一步。
    await saveOcrProviderConfig(
      const OcrProviderConfig(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        model: 'glm-4v-flash',
      ),
    );
  });

  /// 收集 runner 抛出来的各种回调。
  ({
    OcrRunner runner,
    List<String> outcomes,
    List<List<String>> results,
    List<bool> busy,
  }) makeRunner(OcrRecognize recognize) {
    final outcomes = <String>[];
    final results = <List<String>>[];
    final busy = <bool>[];

    final runner = OcrRunner(
      onResult: results.add,
      onStateChange: (s) => busy.add(s.busy),
      onOutcome: outcomes.add,
      onInsufficientCredits: () => outcomes.add('__credits__'),
      onNeedsOcrConfig: () => outcomes.add('__config__'),
      pickPhoto: () async => XFile('fake.jpg'),
      recognize: recognize,
    );
    return (runner: runner, outcomes: outcomes, results: results, busy: busy);
  }

  test('取消会中止识别，而且不再弹一次「失败」', () async {
    final completer = Completer<OcrResult>();
    AbortSignal? captured;

    final h = makeRunner((file, {onProgress, signal}) {
      captured = signal;
      signal?.addListener(() {
        if (!completer.isCompleted) {
          completer.completeError(Exception(kOcrCancelled));
        }
      });
      return completer.future;
    });

    final run = h.runner.processPhoto();
    await Future<void>.delayed(Duration.zero);
    expect(h.runner.busy, isTrue);
    expect(captured, isNotNull);

    h.runner.cancel();
    await run;

    expect(captured!.aborted, isTrue);
    expect(h.runner.busy, isFalse);
    // 取消那一下已经给过反馈了，别再补一句「识别失败」。
    expect(h.outcomes, isEmpty);
    expect(h.results, isEmpty);
  });

  test('超时会说清楚是超时，而不是笼统的失败', () async {
    final h = makeRunner((file, {onProgress, signal}) async {
      throw Exception('识别超时，请检查网络后重试');
    });

    await h.runner.processPhoto();

    expect(h.outcomes, ['识别超时，请检查网络后重试']);
    expect(h.runner.busy, isFalse);
  });

  test('识别成功仍然照常回调，并退出忙碌态', () async {
    final h = makeRunner((file, {onProgress, signal}) async {
      return const OcrResult(words: ['apple', 'banana'], rawText: 'apple');
    });

    await h.runner.processPhoto();

    expect(h.results, [
      ['apple', 'banana']
    ]);
    expect(h.busy.last, isFalse);
  });

  test('闲着的时候取消是空操作', () {
    final h = makeRunner((file, {onProgress, signal}) async {
      return const OcrResult(words: [], rawText: '');
    });

    h.runner.cancel();
    expect(h.runner.busy, isFalse);
    expect(h.outcomes, isEmpty);
  });
}
