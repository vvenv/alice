import 'package:alice_dictation/services/dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

/// 词典资源的载入。
///
/// 3.4MB 的 JSON，启动路径上有三个调用方：main()、首页 _bootstrap、
/// 「开始听写」。以前谁调谁解析一遍 —— `_loaded` 要到最后才置位，并发进来
/// 的几发全部穿过去，首屏白白多卡几百毫秒。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('并发调用共享同一次载入', () async {
    expect(isDictionaryLoaded, isFalse, reason: '这条必须跑在最前面');

    final first = loadDictionary();
    final second = loadDictionary();
    expect(identical(first, second), isTrue,
        reason: '两次调用拿到的不是同一个 Future，说明会解析两遍');

    await Future.wait([first, second]);
    expect(isDictionaryLoaded, isTrue);
  });

  test('载入之后补全能拿到释义', () async {
    await loadDictionary();
    final enriched = enrichWordListText('apple');
    expect(enriched, contains('|'), reason: 'apple 应该补出词性与释义');
  });

  test('重复调用是空操作，不会抛', () async {
    await loadDictionary();
    await loadDictionary();
    expect(isDictionaryLoaded, isTrue);
  });
}
