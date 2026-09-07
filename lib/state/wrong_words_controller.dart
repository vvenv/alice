import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/storage.dart';

/// 错词本状态。对应 RN 版 src/hooks/useWrongWords.ts。
const Duration _flashDuration = Duration(milliseconds: 250);

/// 一轮听写里标记的错词。
///
/// 这一份是**本轮**的：完成页的「错词」计数、「错词再听一遍」都只看它，
/// 所以每开一轮都从空开始。跨轮攒下来的那本在 storage.dart 里（累计错词本，
/// 首页菜单的「错词本」查看的就是它）—— 这里每次增删都同步过去，两边不会长歪。
///
/// 以前构造函数默认从累计本读初值，于是新一轮一进听写页底部就挂着上次的词，
/// 完成卡片的「错词 N」跟着把历史算进去，「再听一遍」还会拉进不在本轮词表里
/// 的词。
class WrongWordsController extends ChangeNotifier {
  WrongWordsController({List<String>? initialWords})
      : _wrongWords = List<String>.from(initialWords ?? const <String>[]);

  List<String> _wrongWords;
  bool _markedFlash = false;
  Timer? _flashTimer;
  bool _disposed = false;

  List<String> get wrongWords => List.unmodifiable(_wrongWords);

  /// 标记瞬间的高亮闪烁（表盘变红）。
  bool get markedFlash => _markedFlash;

  bool get hasWrongWords => _wrongWords.isNotEmpty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void markWrong(String word) {
    if (!_wrongWords.contains(word)) {
      _wrongWords = [..._wrongWords, word];
      unawaited(addWrongWordToBook(word));
    }
    _markedFlash = true;
    _notify();

    _flashTimer?.cancel();
    _flashTimer = Timer(_flashDuration, () {
      _markedFlash = false;
      _notify();
    });
  }

  /// 复制错词到剪贴板，返回给用户看的提示。
  Future<String> exportWrong() async {
    if (_wrongWords.isEmpty) return '暂无错词可导出';
    await Clipboard.setData(ClipboardData(text: _wrongWords.join('\n')));
    return '已复制 ${_wrongWords.length} 个错词';
  }

  /// 清空本轮错词，并把这些词从累计错词本里一并撤掉
  /// —— 用户点「清空」的意思是「这些不算错」，留在累计本里就自相矛盾。
  void clearWrong() {
    final cleared = _wrongWords;
    _wrongWords = <String>[];
    unawaited(removeWrongWordsFromBook(cleared));
    _notify();
  }

  /// 只清掉本轮列表，累计错词本原样保留。
  ///
  /// 「错词再听一遍」用：重听的那一轮要能自己攒出一份新成绩，
  /// 但用户并没有说这些词已经掌握了。
  void resetRound() {
    if (_wrongWords.isEmpty) return;
    _wrongWords = <String>[];
    _notify();
  }

  void removeWrongWord(String word) {
    _wrongWords = _wrongWords.where((w) => w != word).toList();
    unawaited(removeWrongWordsFromBook([word]));
    _notify();
  }

  /// 把词加回来（removeWrongWord 的撤销）—— 不触发标记闪烁。
  void restoreWrongWord(String word) {
    if (_wrongWords.contains(word)) return;
    _wrongWords = [..._wrongWords, word];
    unawaited(addWrongWordToBook(word));
    _notify();
  }

  /// 撤销一次 [clearWrong]：整批加回本轮列表与累计错词本。
  void restoreWrongWords(List<String> words) {
    final restored = <String>[
      ..._wrongWords,
      ...words.where((w) => !_wrongWords.contains(w)),
    ];
    if (restored.length == _wrongWords.length) return;
    _wrongWords = restored;
    for (final word in words) {
      unawaited(addWrongWordToBook(word));
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _flashTimer?.cancel();
    super.dispose();
  }
}
