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
  final pos = parts.length > 1 && parts[1].trim().isNotEmpty
      ? parts[1].trim()
      : null;
  final meaning = parts.length > 2 && parts[2].trim().isNotEmpty
      ? parts[2].trim()
      : null;

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
