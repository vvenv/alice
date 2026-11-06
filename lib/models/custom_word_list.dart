import 'library_item.dart';
import 'word_history_entry.dart';

/// 词库抽屉里用户自建词表的分类名。
const String kCustomLibraryCategory = '我的词库';

/// 用户存下来的一份词表。和首页正在编辑的草稿、上一次听写分开存。
class CustomWordList {
  const CustomWordList({
    required this.id,
    required this.name,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String name;
  final String text;
  final int timestamp;

  LibraryItem toLibraryItem() {
    return LibraryItem(
      entry: WordHistoryEntry(id: id, text: text, timestamp: timestamp),
      category: kCustomLibraryCategory,
      label: name,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'text': text,
        'timestamp': timestamp,
      };

  static CustomWordList? fromJson(Object? item) {
    if (item is! Map) return null;
    final id = item['id'];
    final name = item['name'];
    final text = item['text'];
    final timestamp = item['timestamp'];
    if (id is! String ||
        name is! String ||
        text is! String ||
        timestamp is! num) {
      return null;
    }
    final trimmedName = name.trim();
    final trimmedText = text.trim();
    if (trimmedName.isEmpty || trimmedText.isEmpty) return null;
    return CustomWordList(
      id: id,
      name: trimmedName,
      text: trimmedText,
      timestamp: timestamp.toInt(),
    );
  }
}
