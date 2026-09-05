import 'package:alice_dictation/services/dictation.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

/// 输入词表定稿时按朗读词头去重。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadDictionary);

  test('连续重复只留第一次', () {
    expect(dedupeWordList('apple\napple\nbanana'), 'apple\nbanana');
  });

  test('大小写视为同一词', () {
    expect(dedupeWordList('apple\nApple\nAPPLE'), 'apple');
  });

  test('纯词与带释义的行视为同一词，保留先出现的', () {
    expect(
      dedupeWordList('apple | n. | 苹果\napple\nbanana'),
      'apple | n. | 苹果\nbanana',
    );
    expect(
      dedupeWordList('apple\napple | n. | 苹果'),
      'apple',
    );
  });

  test('展开写法按左侧词头去重', () {
    expect(
      dedupeWordList("you're = you are\nyou're\nyou are"),
      "you're = you are\nyou are",
    );
  });

  test('没有重复时原文行序不变', () {
    expect(dedupeWordList('cat\ndog\nfish'), 'cat\ndog\nfish');
  });

  test('enrichWordListText 定稿时一并去重', () {
    final enriched = enrichWordListText('apple\nbanana\napple\nApple');
    final words = parseWords(enriched).map(speakTextFromEntry).toList();
    expect(words, ['apple', 'banana']);
  });
}
