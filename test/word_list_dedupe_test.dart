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

  // ECDICT 里 name 的末段「名称, 文件名, 姓名」不带词性，并进 n. 组后和前面重复。
  test('同一词性组里重复的释义词条只留一次', () {
    expect(
      splitSenses('名字, 名称, 姓名, 文件名；vt. 命名；名称, 文件名, 姓名', 'n.'),
      ['n. 名字, 名称, 姓名, 文件名', 'vt. 命名'],
    );
    expect(
      splitSenses('名字, 名称；名称, 名誉', 'n.'),
      ['n. 名字, 名称；名誉'],
    );
    // 不同词性组之间不算重复。
    expect(
      splitSenses('n. 会；adj. 会', 'n.'),
      ['n. 会', 'adj. 会'],
    );
  });
}
