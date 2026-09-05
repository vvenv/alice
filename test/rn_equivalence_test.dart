import 'dart:convert';
import 'dart:io';

import 'package:alice_dictation/services/dictation.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/ocr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Expo 版 ↔ Flutter 版的纯逻辑等价性测试。
///
/// `test/golden/rn_golden.json` 是**真的跑 Expo 版的 TypeScript** 生成的，
/// 不是手写的期望值。所以这里断言的是「两版对同一输入给出同一输出」，
/// 而不是「我以为它应该输出什么」。重新生成：
///
/// ```bash
/// bash scripts/rn-golden/generate.sh        # 对齐 main
/// ```
///
/// 覆盖 src/lib/dictation.ts、dictionary.ts 的全部导出函数，以及 ocr.ts 里的
/// extractWordsFromOcrText。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> golden;

  setUpAll(() async {
    final file = File('test/golden/rn_golden.json');
    golden = json.decode(await file.readAsString()) as Map<String, dynamic>;
  });

  List<Map<String, dynamic>> cases(String name) =>
      (golden[name] as List<dynamic>).cast<Map<String, dynamic>>();

  String describe(Object? input) => json.encode(input);

  group('dictation.dart ↔ dictation.ts', () {
    test('parseWords', () {
      for (final c in cases('parseWords')) {
        expect(
          parseWords(c['input'] as String),
          equals((c['output'] as List<dynamic>).cast<String>()),
          reason: 'input=${describe(c['input'])}',
        );
      }
    });

    test('parseWordLine', () {
      for (final c in cases('parseWordLine')) {
        final entry = parseWordLine(c['input'] as String);
        final reason = 'input=${describe(c['input'])}';
        expect(entry.word, equals(c['word']), reason: reason);
        expect(entry.pos, equals(c['pos']), reason: reason);
        expect(entry.meaning, equals(c['meaning']), reason: reason);
      }
    });

    test('parseWordEntries', () {
      for (final c in cases('parseWordEntries')) {
        final entries = parseWordEntries(c['input'] as String);
        final expected =
            (c['output'] as List<dynamic>).cast<Map<String, dynamic>>();
        final reason = 'input=${describe(c['input'])}';

        expect(entries.length, equals(expected.length), reason: reason);
        for (var i = 0; i < entries.length; i++) {
          expect(entries[i].word, equals(expected[i]['word']), reason: reason);
          expect(entries[i].pos, equals(expected[i]['pos']), reason: reason);
          expect(
            entries[i].meaning,
            equals(expected[i]['meaning']),
            reason: reason,
          );
        }
      }
    });

    test('entryToLine', () {
      for (final c in cases('entryToLine')) {
        expect(
          entryToLine(parseWordLine(c['input'] as String)),
          equals(c['output']),
          reason: 'input=${describe(c['input'])}',
        );
      }
    });

    test('speakTextFromEntry', () {
      for (final c in cases('speakTextFromEntry')) {
        expect(
          speakTextFromEntry(c['input'] as String),
          equals(c['output']),
          reason: 'input=${describe(c['input'])}',
        );
      }
    });

    test('normalizePos', () {
      for (final c in cases('normalizePos')) {
        expect(
          normalizePos(c['input'] as String),
          equals(c['output']),
          reason: 'input=${describe(c['input'])}',
        );
      }
    });

    test('speakableMeaning', () {
      for (final c in cases('speakableMeaning')) {
        expect(
          speakableMeaning(c['input'] as String?),
          equals(c['output']),
          reason: 'input=${describe(c['input'])}',
        );
      }
    });
  });

  group('dictionary.dart ↔ dictionary.ts（纯函数）', () {
    test('splitSenses', () {
      for (final c in cases('splitSenses')) {
        expect(
          splitSenses(c['meaning'] as String, c['pos'] as String?),
          equals((c['output'] as List<dynamic>).cast<String>()),
          reason: 'meaning=${describe(c['meaning'])} pos=${describe(c['pos'])}',
        );
      }
    });

    test('sensesClamped', () {
      for (final c in cases('sensesClamped')) {
        expect(
          sensesClamped(
            (c['senses'] as List<dynamic>).cast<String>(),
            c['collapsedLines'] as int,
            c['charsPerLine'] as int,
          ),
          equals(c['output']),
          reason: 'senses=${describe(c['senses'])}',
        );
      }
    });
  });

  group('ocr.dart ↔ ocr.ts', () {
    test('extractWordsFromOcrText', () {
      for (final c in cases('extractWordsFromOcrText')) {
        expect(
          extractWordsFromOcrText(c['input'] as String),
          equals((c['output'] as List<dynamic>).cast<String>()),
          reason: 'input=${describe(c['input'])}',
        );
      }
    });
  });

  group('dictionary.dart ↔ dictionary.ts（需要 ECDICT 资源）', () {
    setUpAll(() async {
      await loadDictionary();
    });

    test('lookupWordMeta', () {
      for (final c in cases('lookupWordMeta')) {
        final meta = lookupWordMeta(c['input'] as String);
        final reason = 'input=${describe(c['input'])}';
        expect(meta?.pos, equals(c['pos']), reason: reason);
        expect(meta?.meaning, equals(c['meaning']), reason: reason);
      }
    });

    test('enrichWordListText', () {
      for (final c in cases('enrichWordListText')) {
        expect(
          enrichWordListText(c['input'] as String),
          equals(c['output']),
          reason: 'input=${describe(c['input'])}',
        );
      }
    });
  });
}
