import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/services/storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 历史记录的持久化。用户报过「听写开始/完成后没有保存为历史记录」，
/// 这里把那条路径钉死。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // setMockInitialValues 只重置 SharedPreferences 自己的缓存，
  // 而 Prefs 把实例存在静态字段里（`_instance ??=`），第二次 init 是空操作 ——
  // 每个用例再调一次只会让 Prefs 抱着上一份带旧数据的实例。所以初始化一次，
  // 用例之间走公开 API 清空。
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadLibrary();
  });

  setUp(() async {
    await clearWordHistory();
  });

  test('自己输入的词表会写进历史', () async {
    await addWordHistory('apple\nbanana\ncat');

    final history = await loadWordHistory();
    expect(history, hasLength(1));
    expect(history.first.text, 'apple\nbanana\ncat');
  });

  test('带词性释义的补全文本同样会写进历史', () async {
    await addWordHistory('apple | n. | 苹果\nbanana | n. | 香蕉');

    final history = await loadWordHistory();
    expect(history, hasLength(1));
  });

  test('重复听写同一份词表只留一条，时间戳前移', () async {
    await addWordHistory('apple\nbanana');
    final first = (await loadWordHistory()).single;

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await addWordHistory('apple\nbanana');
    final again = await loadWordHistory();

    expect(again, hasLength(1));
    expect(again.single.id, first.id);
    expect(again.single.timestamp, greaterThanOrEqualTo(first.timestamp));
  });

  test('内置词表不产生用户历史', () async {
    final groups = getLibraryGroups();
    final sample = groups.first.items.first.entry.text;

    await addWordHistory(sample);

    expect(await loadWordHistory(), isEmpty);
  });

  test('空输入不写历史', () async {
    await addWordHistory('   ');
    expect(await loadWordHistory(), isEmpty);
  });

  // 内置词表是故意不入历史的（Expo 版 storage.ts 里同一条规则），
  // 但它得能从「词库」里选出来 —— 两件事不要混为一谈。
  test('内置词表仍然出现在词库分组里', () async {
    final groups = getLibraryGroups();
    expect(groups, isNotEmpty);
    expect(groups.first.items, isNotEmpty);
  });

  // 首页真实路径：开始听写前会先跑一遍 enrichWordListText 再写历史。
  test('示例词表按首页的完整路径也能写进历史', () async {
    const sample = 'apple\nbanana\ncat\ndog\nelephant\nfish\ngrape';
    await loadDictionary();

    final enriched = enrichWordListText(sample);
    await addWordHistory(enriched);

    final history = await loadWordHistory();
    expect(history, hasLength(1));
    expect(history.first.text, enriched);
  });
}
