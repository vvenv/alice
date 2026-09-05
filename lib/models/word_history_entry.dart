/// 一条单词表记录（用户历史 or 内置词库条目）。
///
/// 对应 RN 版 src/lib/storage.ts 的 WordHistoryEntry。
class WordHistoryEntry {
  const WordHistoryEntry({
    required this.id,
    required this.text,
    required this.timestamp,
    this.enrichedText,
  });

  final String id;
  final String text;
  final int timestamp;

  /// 补全后的版本（word | pos | meaning）—— 作为展开数据存储，
  /// 原始的纯单词 `text` 保持不变，历史记录仍按原文展示。
  final String? enrichedText;

  WordHistoryEntry copyWith({
    String? id,
    String? text,
    int? timestamp,
    String? enrichedText,
  }) {
    return WordHistoryEntry(
      id: id ?? this.id,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      enrichedText: enrichedText ?? this.enrichedText,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'timestamp': timestamp,
        if (enrichedText != null && enrichedText!.isNotEmpty)
          'enrichedText': enrichedText,
      };

  /// 宽松解析 —— 字段类型不对就返回 null，由调用方丢弃这一行。
  /// 对应 RN 版的 sanitizeEntry。
  static WordHistoryEntry? fromJson(Object? item) {
    if (item is! Map) return null;
    final id = item['id'];
    final text = item['text'];
    final timestamp = item['timestamp'];
    if (id is! String || text is! String || timestamp is! num) return null;

    final enriched = item['enrichedText'];
    return WordHistoryEntry(
      id: id,
      text: text,
      timestamp: timestamp.toInt(),
      enrichedText: enriched is String && enriched.isNotEmpty ? enriched : null,
    );
  }
}
