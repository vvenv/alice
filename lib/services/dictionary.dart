import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'dictation.dart';

/// 离线英汉词条元数据（词性 + 释义），数据来自 ECDICT。
///
/// 数据集：https://github.com/skywind3000/ECDICT (MIT)
/// 由 RN 版的 `pnpm dict:build` → scripts/build-ecdict-meta.py 生成，
/// 这里直接复用同一份 JSON（assets/data/ecdict-meta.json）。
///
/// 对应 RN 版 src/lib/dictionary.ts。
class WordMeta {
  const WordMeta({this.pos, this.meaning});

  final String? pos;
  final String? meaning;

  bool get isEmpty =>
      (pos == null || pos!.isEmpty) && (meaning == null || meaning!.isEmpty);
}

/// 紧凑映射：小写单词 → `"pos|meaning"`（pos 可能为空）。
Map<String, String> _meta = const {};
bool _loaded = false;

/// 在启动时载入词典资源。3.4MB JSON，解析一次常驻内存。
Future<void> loadDictionary() async {
  if (_loaded) return;
  final raw = await rootBundle.loadString('assets/data/ecdict-meta.json');
  final decoded = json.decode(raw) as Map<String, dynamic>;
  _meta = decoded.map((k, v) => MapEntry(k, v as String));
  _loaded = true;
}

final RegExp _posPrefixRe = RegExp(
  r'^(n\.|v\.|vt\.|vi\.|adj\.|adv\.|prep\.|conj\.|pron\.|num\.|art\.|int\.|aux\.|abbr\.|contr\.|a\.)\s*',
  caseSensitive: false,
);

/// 仅做清理，保留完整释义（含多义项）。多义项以「；」分隔，由构建脚本保证。
String _normalizeMeaning(String raw) => raw.trim();

/// 将释义按词性分组：同一词性的多个义项合并为一行（「；」连接），不同词性各占一行。
///
/// 返回的每行自带词性前缀（主词性组使用 mainPos）；无词性前缀的义项归入主词性组。
List<String> splitSenses(String meaning, [String? mainPos]) {
  final mainKey = (mainPos ?? '').toLowerCase();
  // LinkedHashMap 语义 —— Dart 的 Map 字面量保持插入顺序，与 JS Map 一致。
  final groups = <String, List<String>>{};

  for (final raw in meaning.split(RegExp('[；;]'))) {
    final seg = raw.trim();
    if (seg.isEmpty) continue;

    final m = _posPrefixRe.firstMatch(seg);
    var key = mainKey;
    var text = seg;
    if (m != null) {
      key = m.group(1)!.toLowerCase();
      if (key == 'a.') key = 'adj.';
      text = seg.substring(m.group(0)!.length).trim();
    }
    if (text.isEmpty) continue;

    groups.putIfAbsent(key, () => <String>[]).add(text);
  }

  // 主词性组置顶，其余按首次出现顺序
  final keys = groups.keys.toList();
  final ordered = mainKey.isNotEmpty && groups.containsKey(mainKey)
      ? <String>[mainKey, ...keys.where((k) => k != mainKey)]
      : keys;

  return ordered.map((key) {
    final parts = groups[key]!.join('；');
    if (key == mainKey) {
      return (mainPos != null && mainPos.isNotEmpty)
          ? '$mainPos $parts'
          : parts;
    }
    return '$key $parts';
  }).toList();
}

/// 估算分组释义在折叠行数内是否显示不全（决定「展开」开关是否出现）。
///
/// 按视觉宽度粗略折算：全角字符（CJK、全角标点）记 1 字宽，其余记 0.5；
/// charsPerLine 为每行可容纳的字宽数，宁可低估容量（多显示开关）也不要漏判。
bool sensesClamped(List<String> senses, int collapsedLines, int charsPerLine) {
  double width(String s) => s.runes.fold<double>(
        0,
        (w, ch) => w + (ch > 0x2e7f ? 1 : 0.5),
      );

  final lines = senses.fold<int>(
    0,
    (n, s) => n + math.max(1, (width(s) / charsPerLine).ceil()),
  );
  return lines > collapsedLines;
}

/// 把 `"n. 苹果"` 这样的释义拆成 `{ pos, meaning }`。
WordMeta? _splitPosMeaning(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('【')) return null;

  String? pos;
  final posMatch = _posPrefixRe.firstMatch(text);
  if (posMatch != null) {
    pos = posMatch.group(1)!.toLowerCase();
    if (pos == 'a.') pos = 'adj.';
    text = text.substring(posMatch.group(0)!.length).trim();
  }

  text = _normalizeMeaning(text);
  if (pos == null && text.isEmpty) return null;
  return WordMeta(pos: pos, meaning: text.isNotEmpty ? text : null);
}

WordMeta? _decodeStored(String raw) {
  // 存储格式为 "pos|meaning"（pos 可空 → "|meaning"）
  final bar = raw.indexOf('|');
  if (bar == -1) return _splitPosMeaning(raw);

  final pos = raw.substring(0, bar).trim();
  final meaning = _normalizeMeaning(raw.substring(bar + 1));
  if (pos.isEmpty && meaning.isEmpty) return null;
  return WordMeta(
    pos: pos.isNotEmpty ? pos : null,
    meaning: meaning.isNotEmpty ? meaning : null,
  );
}

/// 在离线 ECDICT 子集中查一个单词/词组。大小写不敏感；查不到返回 null。
WordMeta? lookupWordMeta(String word) {
  final key = word.trim().toLowerCase();
  if (key.isEmpty) return null;

  final direct = _meta[key];
  if (direct != null) return _decodeStored(direct);

  // 去掉 OCR 常留下的尾部标点 / 软连字符
  final stripped = key
      .replaceAll(RegExp(r"[^a-z0-9\s'\-./]", caseSensitive: false), '')
      .trim();
  if (stripped.isNotEmpty && stripped != key) {
    final again = _meta[stripped];
    if (again != null) return _decodeStored(again);
  }

  // "a/an" 这类并列写法 —— 两边分别试
  if (key.contains('/')) {
    for (final part in key.split('/')) {
      final meta = lookupWordMeta(part);
      if (meta != null) return meta;
    }
  }

  return null;
}

/// 用离线词典给多行单词表补上词性 + 释义。
///
/// 已经带 `| pos | meaning` 的行原样保留；查不到的行保持纯单词。
/// 同步且很便宜 —— 用在「完成」/ 开始听写这两个时机。
String enrichWordListText(String text) {
  return parseWords(text).map((line) {
    final entry = parseWordLine(line);
    if (entry.hasMeta) return line;

    final speakable = speakTextFromEntry(line);
    final meta = lookupWordMeta(speakable);
    if (meta == null || meta.isEmpty) return line;

    return entryToLine(
      WordEntry(word: entry.word, pos: meta.pos, meaning: meta.meaning),
    );
  }).join('\n');
}
