import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/storage.dart';

/// 错词本状态。对应 RN 版 src/hooks/useWrongWords.ts。
const Duration _flashDuration = Duration(milliseconds: 250);

class WrongWordsController extends ChangeNotifier {
  WrongWordsController({List<String>? initialWords})
      : _wrongWords = List<String>.from(initialWords ?? loadWrongWords());

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
      saveWrongWords(_wrongWords);
    }
    _markedFlash = true;
    _notify();

    _flashTimer?.cancel();
    _flashTimer = Timer(_flashDuration, () {
      _markedFlash = false;
      _notify();
    });
  }

  /// 复制错词到剪贴板，返回给用户看的提示（无错词时返回空串）。
  Future<String> exportWrong() async {
    if (_wrongWords.isEmpty) return '';
    await Clipboard.setData(ClipboardData(text: _wrongWords.join('\n')));
    return '已复制 ${_wrongWords.length} 个错词';
  }

  String clearWrong() {
    _wrongWords = <String>[];
    saveWrongWords(_wrongWords);
    _notify();
    return '已清空错词本';
  }

  void removeWrongWord(String word) {
    _wrongWords = _wrongWords.where((w) => w != word).toList();
    saveWrongWords(_wrongWords);
    _notify();
  }

  /// 把词加回来（removeWrongWord 的撤销）—— 不触发标记闪烁。
  void restoreWrongWord(String word) {
    if (_wrongWords.contains(word)) return;
    _wrongWords = [..._wrongWords, word];
    saveWrongWords(_wrongWords);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _flashTimer?.cancel();
    super.dispose();
  }
}
