import 'word_history_entry.dart';

/// 内置词库的一条词表。对应 RN 版 src/lib/library.ts 的 LibraryItem。
class LibraryItem {
  const LibraryItem({
    required this.entry,
    required this.category,
    required this.label,
  });

  final WordHistoryEntry entry;

  /// 分类，如 "中考1600" / "人教版初中"
  final String category;

  /// 词表名，如 "七上 Unit 1"
  final String label;

  static LibraryItem fromJson(Map<String, dynamic> json) {
    return LibraryItem(
      entry: WordHistoryEntry.fromJson(json['entry'])!,
      category: json['category'] as String,
      label: json['label'] as String,
    );
  }
}

/// 词库抽屉里按分类分组的结构。
class LibraryGroup {
  const LibraryGroup({required this.category, required this.items});

  final String category;
  final List<LibraryItem> items;
}
