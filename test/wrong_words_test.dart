import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/services/storage.dart';
import 'package:alice_dictation/state/wrong_words_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 错词的两份账：**本轮**标记了哪些（完成页的成绩、「错词再听一遍」看它）
/// 与跨轮累计的**错词本**（首页菜单里查看的那本）。
///
/// 0.7.6 之前只有一份：听写页的控制器默认从累计本读初值，于是新一轮一进页
/// 底部就挂着上次的错词，完成卡片的「错词 N」把历史一起算了进去，
/// 「再听一遍」还会拉进不在本轮词表里的词。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
  });

  setUp(() async {
    await clearWrongWordsBook();
  });

  test('新一轮从空开始，不继承累计错词本', () async {
    await addWrongWordToBook('apple');
    await addWrongWordToBook('banana');
    expect(loadWrongWords(), ['apple', 'banana']);

    final c = WrongWordsController();
    addTearDown(c.dispose);

    expect(c.wrongWords, isEmpty, reason: '本轮成绩不该带上历史错词');
    expect(loadWrongWords(), ['apple', 'banana'], reason: '累计本原样保留');
  });

  test('标记错词会同时进本轮列表和累计错词本', () async {
    final c = WrongWordsController();
    addTearDown(c.dispose);

    c.markWrong('cat');
    await pumpEventQueue();

    expect(c.wrongWords, ['cat']);
    expect(loadWrongWords(), ['cat']);
  });

  test('重复标记同一个词只记一次', () async {
    final c = WrongWordsController();
    addTearDown(c.dispose);

    c.markWrong('cat');
    c.markWrong('cat');
    await pumpEventQueue();

    expect(c.wrongWords, ['cat']);
    expect(loadWrongWords(), ['cat']);
  });

  test('移除错词两边一起移除', () async {
    await addWrongWordToBook('old');
    final c = WrongWordsController();
    addTearDown(c.dispose);

    c.markWrong('cat');
    await pumpEventQueue();
    c.removeWrongWord('cat');
    await pumpEventQueue();

    expect(c.wrongWords, isEmpty);
    expect(loadWrongWords(), ['old'], reason: '别的轮次标的词不受影响');
  });

  test('清空会把本轮的词从累计错词本里一并撤掉，但不碰别的词', () async {
    await addWrongWordToBook('old');
    final c = WrongWordsController();
    addTearDown(c.dispose);

    c.markWrong('cat');
    c.markWrong('dog');
    await pumpEventQueue();

    c.clearWrong();
    await pumpEventQueue();

    expect(c.wrongWords, isEmpty);
    expect(loadWrongWords(), ['old']);
  });

  test('清空可以整批撤销', () async {
    final c = WrongWordsController();
    addTearDown(c.dispose);

    c.markWrong('cat');
    c.markWrong('dog');
    await pumpEventQueue();
    final cleared = c.wrongWords;

    c.clearWrong();
    await pumpEventQueue();
    c.restoreWrongWords(cleared);
    await pumpEventQueue();

    expect(c.wrongWords, ['cat', 'dog']);
    expect(loadWrongWords(), ['cat', 'dog']);
  });

  // 「错词再听一遍」：重听的那一轮要自己攒一份成绩，但用户并没有说这些词
  // 已经掌握了 —— 累计本必须留着。
  test('resetRound 只清本轮，累计错词本原样保留', () async {
    final c = WrongWordsController();
    addTearDown(c.dispose);

    c.markWrong('cat');
    c.markWrong('dog');
    await pumpEventQueue();

    c.resetRound();
    await pumpEventQueue();

    expect(c.wrongWords, isEmpty);
    expect(loadWrongWords(), ['cat', 'dog']);
  });

  test('累计错词本的增删是幂等的', () async {
    await addWrongWordToBook('cat');
    await addWrongWordToBook('cat');
    expect(loadWrongWords(), ['cat']);

    await removeWrongWordsFromBook(['nope']);
    expect(loadWrongWords(), ['cat']);

    await removeWrongWordsFromBook(['cat']);
    expect(loadWrongWords(), isEmpty);
  });
}
