import 'dart:convert';
import 'dart:math';

import 'package:flutter/painting.dart';

import '../models/word_history_entry.dart';
import 'dictation.dart';
import 'library_data.dart';
import 'prefs.dart';

/// 应用数据持久化。对应 RN 版 src/lib/storage.ts。
/// 所有 key 与 RN 版保持一致。
const String _wrongWordsKey = 'dictation_wrong_words';
const String _wordInputKey = 'dictation_word_input';
const String _wordHistoryKey = 'dictation_word_history';
const String _favoritesKey = 'dictation_favorites';
const String _speechRateKey = 'dictation_speech_rate';
const String _intervalSecKey = 'dictation_interval_sec';
// Flutter 版独有（RN 版的拍照按钮不能拖），所以不走 dictation_ 前缀。
const String _cameraButtonPosKey = 'alice_camera_button_pos';

/// 用户历史条数上限。内置词表存在代码/资源里，不占用存储。
const int _maxUserHistoryEntries = 50;

const double kDefaultSpeechRate = 0.9;
const double kMinSpeechRate = 0.5;
const double kMaxSpeechRate = 1.5;
const double kDefaultIntervalSec = 7;
const double kMinIntervalSec = 1;
const double kMaxIntervalSec = 10;
const double kIntervalStep = 0.5;

/// 内置词库条目的 id 前缀。`default_` 是为了兼容早期把词库行写进存储的安装包。
bool isLibraryId(String id) => id.startsWith('default_');

/// 归一化单词表以便比较：剥掉词性/释义，只留可朗读的词头，
/// 这样补全过的文本仍能与它对应的纯词库文本匹配上。
String plainWordList(String text) {
  return parseWords(text)
      .map(speakTextFromEntry)
      .where((s) => s.isNotEmpty)
      .join('\n');
}

/// 内置词库文本的归一化集合。
///
/// RN 版每次比较都要把 290 条词表重新归一化一遍；这里缓存成 Set，
/// 语义不变但把 O(n·len) 的重复计算降成一次。
Set<String>? _libraryPlainCache;

Set<String> get _libraryPlainSet {
  return _libraryPlainCache ??= {
    for (final item in libraryItems) plainWordList(item.entry.text),
  };
}

bool _matchesLibraryText(String text) {
  final plain = plainWordList(text);
  if (plain.isEmpty) return false;
  return _libraryPlainSet.contains(plain);
}

/// 清洗存储行为干净的用户条目：
/// - 丢掉词库 id 的行（早期版本把内置词表也持久化了）
/// - 丢掉正文与内置词表重复的行
/// - 截断到 _maxUserHistoryEntries
List<WordHistoryEntry> _toUserEntries(List<WordHistoryEntry> stored) {
  final filtered = stored
      .where((e) => !isLibraryId(e.id))
      .where((e) => !_matchesLibraryText(e.text))
      .where((e) =>
          !(e.enrichedText != null && _matchesLibraryText(e.enrichedText!)))
      .toList();
  return filtered.length > _maxUserHistoryEntries
      ? filtered.sublist(0, _maxUserHistoryEntries)
      : filtered;
}

Future<void> _persistHistory(List<WordHistoryEntry> entries) async {
  await Prefs.setString(
    _wordHistoryKey,
    json.encode(entries.map((e) => e.toJson()).toList()),
  );
}

// --- 错词本 ---------------------------------------------------------------
//
// 这里存的是**累计**错词本：跨轮次攒下来的、还没消化掉的词。
// 单轮听写标记了哪些词是另一回事（见 WrongWordsController），完成页的成绩
// 只看那一份。两边通过下面这几个增量操作保持同步。

List<String> _cachedWrongWords = <String>[];

/// 同步读取内存缓存 —— 对应 RN 版的 loadWrongWords()。
List<String> loadWrongWords() => List.unmodifiable(_cachedWrongWords);

/// 往累计错词本里加一个词（已存在则原样返回）。
Future<void> addWrongWordToBook(String word) async {
  if (word.isEmpty || _cachedWrongWords.contains(word)) return;
  await saveWrongWords([..._cachedWrongWords, word]);
}

/// 从累计错词本里移除若干词。
Future<void> removeWrongWordsFromBook(Iterable<String> words) async {
  final drop = words.toSet();
  if (drop.isEmpty) return;
  final next = _cachedWrongWords.where((w) => !drop.contains(w)).toList();
  if (next.length == _cachedWrongWords.length) return;
  await saveWrongWords(next);
}

/// 清空累计错词本。
Future<void> clearWrongWordsBook() => saveWrongWords(<String>[]);

Future<List<String>> loadPersistedWrongWords() async {
  try {
    final data = await Prefs.getString(_wrongWordsKey);
    if (data == null || data.isEmpty) {
      _cachedWrongWords = <String>[];
      return _cachedWrongWords;
    }
    final parsed = json.decode(data);
    _cachedWrongWords =
        parsed is List ? parsed.whereType<String>().toList() : <String>[];
  } catch (_) {
    _cachedWrongWords = <String>[];
  }
  return List.unmodifiable(_cachedWrongWords);
}

Future<void> saveWrongWords(List<String> words) async {
  _cachedWrongWords = List<String>.from(words);
  try {
    await Prefs.setString(_wrongWordsKey, json.encode(words));
  } catch (_) {
    // 忽略 —— 内存里仍然是对的
  }
}

// --- 单词输入框草稿 -------------------------------------------------------

Future<String?> loadWordInput() async {
  try {
    return await Prefs.getString(_wordInputKey);
  } catch (_) {
    return null;
  }
}

Future<void> saveWordInput(String value) async {
  try {
    await Prefs.setString(_wordInputKey, value);
  } catch (_) {
    // 忽略
  }
}

// --- 历史记录 -------------------------------------------------------------

/// 只载入用户历史。内置词表通过 getLibraryGroups() 提供。
/// 老安装包里持久化过的词库行会被自动清理掉。
Future<List<WordHistoryEntry>> loadWordHistory() async {
  try {
    final data = await Prefs.getString(_wordHistoryKey);
    if (data == null || data.isEmpty) return <WordHistoryEntry>[];

    final parsed = json.decode(data);
    final stored = parsed is List
        ? parsed
            .map(WordHistoryEntry.fromJson)
            .whereType<WordHistoryEntry>()
            .toList()
        : <WordHistoryEntry>[];

    final users = _toUserEntries(stored);
    // 发现残留的词库行就顺手修好存储。
    if (users.length != stored.length) {
      await _persistHistory(users);
    }
    return users;
  } catch (_) {
    return <WordHistoryEntry>[];
  }
}

final Random _random = Random();

String _generateEntryId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final suffix =
      List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
  return '${DateTime.now().millisecondsSinceEpoch}_$suffix';
}

Future<void> addWordHistory(String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;
  // 从内置词表开始听写不应该创建用户历史行。
  if (_matchesLibraryText(trimmed)) return;

  try {
    final users = await loadWordHistory();
    final now = DateTime.now().millisecondsSinceEpoch;

    WordHistoryEntry? existing;
    for (final e in users) {
      if (e.text == trimmed || e.enrichedText == trimmed) {
        existing = e;
        break;
      }
    }

    final List<WordHistoryEntry> next;
    if (existing != null) {
      next = [
        existing.copyWith(timestamp: now),
        ...users.where((e) => e.id != existing!.id),
      ];
    } else {
      next = [
        WordHistoryEntry(id: _generateEntryId(), text: trimmed, timestamp: now),
        ...users,
      ];
    }

    await _persistHistory(
      next.length > _maxUserHistoryEntries
          ? next.sublist(0, _maxUserHistoryEntries)
          : next,
    );
  } catch (_) {
    // 忽略
  }
}

Future<void> deleteWordHistory(String id) async {
  if (isLibraryId(id)) return;
  try {
    final users = await loadWordHistory();
    await _persistHistory(users.where((e) => e.id != id).toList());
    // 顺带删掉指向它的收藏，避免悬空。
    if (_cachedFavorites.contains(id)) {
      await saveFavorites(_cachedFavorites.where((x) => x != id).toList());
    }
  } catch (_) {
    // 忽略
  }
}

Future<void> clearWordHistory() async {
  try {
    await _persistHistory(<WordHistoryEntry>[]);
    // 保留词库收藏；丢掉指向已删历史行的收藏。
    final remaining = _cachedFavorites.where(isLibraryId).toList();
    if (remaining.length != _cachedFavorites.length) {
      await saveFavorites(remaining);
    }
  } catch (_) {
    // 忽略
  }
}

// --- 收藏 -----------------------------------------------------------------
// 收藏存的是稳定 id：内置词库为 `default_<category>_<label>`，
// 用户历史为生成的时间戳 id。

List<String> _cachedFavorites = <String>[];

List<String> loadFavorites() => List.unmodifiable(_cachedFavorites);

Future<List<String>> loadPersistedFavorites() async {
  try {
    final data = await Prefs.getString(_favoritesKey);
    if (data == null || data.isEmpty) {
      _cachedFavorites = <String>[];
      return _cachedFavorites;
    }
    final parsed = json.decode(data);
    _cachedFavorites =
        parsed is List ? parsed.whereType<String>().toList() : <String>[];
  } catch (_) {
    _cachedFavorites = <String>[];
  }
  return List.unmodifiable(_cachedFavorites);
}

Future<void> saveFavorites(List<String> ids) async {
  _cachedFavorites = List<String>.from(ids);
  try {
    await Prefs.setString(_favoritesKey, json.encode(ids));
  } catch (_) {
    // 忽略
  }
}

bool isFavorite(String id) => _cachedFavorites.contains(id);

/// 切换收藏状态，返回切换后的状态。
Future<bool> toggleFavorite(String id) async {
  final next = _cachedFavorites.contains(id)
      ? _cachedFavorites.where((x) => x != id).toList()
      : [..._cachedFavorites, id];
  await saveFavorites(next);
  return next.contains(id);
}

// --- 语速 -----------------------------------------------------------------

double clampSpeechRate(double rate) =>
    rate.clamp(kMinSpeechRate, kMaxSpeechRate).toDouble();

Future<double> loadSpeechRate() async {
  try {
    final data = await Prefs.getString(_speechRateKey);
    if (data == null || data.isEmpty) return kDefaultSpeechRate;
    final parsed = double.tryParse(data);
    return parsed != null && parsed.isFinite
        ? clampSpeechRate(parsed)
        : kDefaultSpeechRate;
  } catch (_) {
    return kDefaultSpeechRate;
  }
}

Future<void> saveSpeechRate(double rate) async {
  try {
    await Prefs.setString(_speechRateKey, clampSpeechRate(rate).toString());
  } catch (_) {
    // 忽略
  }
}

// --- 播放间隔 -------------------------------------------------------------

double clampIntervalSec(double sec) {
  final snapped = (sec / kIntervalStep).round() * kIntervalStep;
  return snapped.clamp(kMinIntervalSec, kMaxIntervalSec).toDouble();
}

Future<double> loadIntervalSec() async {
  try {
    final data = await Prefs.getString(_intervalSecKey);
    if (data == null || data.isEmpty) return kDefaultIntervalSec;
    final parsed = double.tryParse(data);
    return parsed != null && parsed.isFinite
        ? clampIntervalSec(parsed)
        : kDefaultIntervalSec;
  } catch (_) {
    return kDefaultIntervalSec;
  }
}

Future<void> saveIntervalSec(double sec) async {
  try {
    await Prefs.setString(_intervalSecKey, clampIntervalSec(sec).toString());
  } catch (_) {
    // 忽略
  }
}

// --- 拍照按钮的落点 -------------------------------------------------------

/// 拍照按钮默认停在单词卡片的右下角。
///
/// 存的是 [Alignment]（-1 ~ 1）而不是像素：换机型、转屏、键盘顶起来把卡片压扁，
/// 按钮都还停在用户放的那个相对位置上。
const Alignment kDefaultCameraButtonAlignment = Alignment.bottomRight;

Alignment clampCameraButtonAlignment(Alignment a) => Alignment(
      a.x.isFinite ? a.x.clamp(-1.0, 1.0).toDouble() : 1,
      a.y.isFinite ? a.y.clamp(-1.0, 1.0).toDouble() : 1,
    );

Future<Alignment> loadCameraButtonAlignment() async {
  try {
    final data = await Prefs.getString(_cameraButtonPosKey);
    if (data == null || data.isEmpty) return kDefaultCameraButtonAlignment;
    final parts = data.split(',');
    if (parts.length != 2) return kDefaultCameraButtonAlignment;
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    if (x == null || y == null) return kDefaultCameraButtonAlignment;
    return clampCameraButtonAlignment(Alignment(x, y));
  } catch (_) {
    return kDefaultCameraButtonAlignment;
  }
}

Future<void> saveCameraButtonAlignment(Alignment a) async {
  try {
    final safe = clampCameraButtonAlignment(a);
    await Prefs.setString(_cameraButtonPosKey, '${safe.x},${safe.y}');
  } catch (_) {
    // 忽略
  }
}
