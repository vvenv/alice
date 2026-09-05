/// 单词列表文本的解析工具。对应 RN 版 src/lib/dictation.ts。
library;

/// 把多行输入拆成条目（每个非空行一条）。
List<String> parseWords(String text) {
  return text
      .split(RegExp(r'[\n\r]+'))
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();
}

/// 一行解析出来的结构化条目。
class WordEntry {
  const WordEntry({required this.word, this.pos, this.meaning});

  /// 单词/词组（可能含 = 展开语法）
  final String word;

  /// 词性，如 "n." "v." "adj."
  final String? pos;

  /// 中文释义
  final String? meaning;

  bool get hasMeta =>
      (pos != null && pos!.isNotEmpty) ||
      (meaning != null && meaning!.isNotEmpty);
}

/// 词性前缀（ECDICT 与用户词表通用），如 "n." "vt." "adj."。
///
/// 这一份是共享的：dictionary.dart 与 build-ecdict-meta.py 认的是同一套缩写，
/// 分开写过一次，结果两边慢慢长歪了。
final RegExp posPrefixRe = RegExp(
  r'^(n\.|v\.|vt\.|vi\.|adj\.|adv\.|prep\.|conj\.|pron\.|num\.|art\.|int\.|'
  r'interj\.|aux\.|abbr\.|contr\.|pl\.|a\.|na\.|un\.|vbl\.|pp\.|pn\.|exclam\.|'
  r'pref\.|suf\.|suff\.|comb\.|quant\.|phr\.|ph\.|st\.|pr\.|ind\.|pers\.|col\.|'
  r'ing\.|pla\.|stuff\.)\s*',
  caseSensitive: false,
);

/// 归一化词性缩写（ECDICT 原文与教材习惯的差异，构建脚本同款映射）：
/// interj./exclam.→int.，na./un./pla./pn.→n.，vbl./pp.→v.，
/// pref./suf./suff./comb./stuff.→abbr.，a.→adj.，pl.→n.
String normalizePos(String pos) {
  final key = pos.trim().toLowerCase();
  switch (key) {
    case 'a.':
      return 'adj.';
    case 'pl.':
    case 'na.':
    case 'un.':
    case 'pla.':
    case 'pn.':
      return 'n.';
    case 'interj.':
    case 'exclam.':
      return 'int.';
    case 'vbl.':
    case 'pp.':
      return 'v.';
    case 'pref.':
    case 'suf.':
    case 'suff.':
    case 'comb.':
    case 'stuff.':
      return 'abbr.';
    default:
      return key;
  }
}

const String _pipe = '|';
const String _fullwidthPipe = '｜';

/// 解析单行。
///
/// 格式：`word | pos | meaning`（竖线分隔）。只有 `word` 是必需的；
/// 没有竖线的行就是纯单词。
WordEntry parseWordLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return const WordEntry(word: '');

  final parts = trimmed.split(RegExp('[$_pipe$_fullwidthPipe]'));
  final word = parts.isNotEmpty ? parts[0].trim() : '';
  final pos =
      parts.length > 1 && parts[1].trim().isNotEmpty ? parts[1].trim() : null;
  final meaning =
      parts.length > 2 && parts[2].trim().isNotEmpty ? parts[2].trim() : null;

  return WordEntry(word: word, pos: pos, meaning: meaning);
}

/// 解析多行为结构化条目。
List<WordEntry> parseWordEntries(String text) =>
    parseWords(text).map(parseWordLine).toList();

/// 把 WordEntry 序列化回一行字符串。
String entryToLine(WordEntry entry) {
  if (entry.pos == null && entry.meaning == null) return entry.word;
  return [entry.word, entry.pos ?? '', entry.meaning ?? ''].join(' $_pipe ');
}

/// 该条目实际要朗读的文本。
///
/// - 去掉 `|` 后面的词性/释义（TTS 不能把它们念出来）。
/// - 支持 `you're = you are` 这类展开写法：朗读左侧（`you're`），
///   而整行仍然作为展示/答案文本。
String speakTextFromEntry(String entry) {
  var text = entry.trim();
  if (text.isEmpty) return '';

  final pipe = text.indexOf(_pipe);
  if (pipe != -1) text = text.substring(0, pipe).trim();
  if (text.isEmpty) return '';

  final eq = text.indexOf(RegExp('[=＝]'));
  if (eq == -1) return text;

  final left = text.substring(0, eq).trim();
  return left.isNotEmpty ? left : text;
}

final RegExp _senseSplitRe = RegExp('[；;]');
final RegExp _glossSplitRe = RegExp('[，,、]');
final RegExp _meaningParenRe = RegExp(r'[（(][^（）()]*[）)]');
final RegExp _meaningEdgePunctRe =
    RegExp(r'^[\s，,、。.：:；;]+|[\s，,、。.：:；;]+$');

/// 朗读释义的长度上限（视觉宽度，全角 1、半角 0.5），超过则截取首个词条。
const double _speakMeaningMaxWidth = 12;

/// 全角记 1 字宽、半角记 0.5（与 dictionary.dart 的 sensesClamped 同一口径）。
double _meaningWidth(String text) {
  var width = 0.0;
  for (final rune in text.runes) {
    width += rune > 0x2e7f ? 1 : 0.5;
  }
  return width;
}

/// 朗读用的中文释义。与释义展示不同，TTS 只需要最核心的一个意思：
///
/// - 去掉词性前缀（"n." "vt." 等会被 TTS 逐字念出）；
/// - 多义项（「；」分隔，构建脚本与 enrichWordListText 保证）只取第一个非空义项；
/// - 括号补注（缩写的英文全称等）不朗读；
/// - 首义项仍超长时（同义词枚举）截取首个词条。
///
/// 返回空串表示没有可朗读的内容（如整个释义只有词性标记）。
String speakableMeaning(String? meaning) {
  if (meaning == null || meaning.isEmpty) return '';

  for (final raw in meaning.split(_senseSplitRe)) {
    var text = raw.trim();
    final pos = posPrefixRe.firstMatch(text);
    if (pos != null) text = text.substring(pos.group(0)!.length).trim();
    text = text.replaceAll(_meaningParenRe, '').trim();
    text = text.replaceAll(_meaningEdgePunctRe, '');
    if (text.isEmpty) continue;

    if (_meaningWidth(text) > _speakMeaningMaxWidth) {
      text = text.split(_glossSplitRe).first;
      text = text.replaceAll(_meaningEdgePunctRe, '');
      if (text.isEmpty) continue;
    }
    return text;
  }
  return '';
}
