import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/library_item.dart';

/// 内置词库。RN 版把它生成成 16k 行的 library.ts（代码即数据）；
/// Flutter 侧改成 assets/data/library.json，启动时解析一次。
///
/// JSON 由 scripts/export-library-json.mjs 从 src/lib/library.ts 转出，
/// 结构与字段完全一致，是唯一数据源，运行时永不修改。
List<LibraryItem> _items = const [];
bool _loaded = false;

Future<void> loadLibrary() async {
  if (_loaded) return;
  final raw = await rootBundle.loadString('assets/data/library.json');
  final decoded = json.decode(raw) as List<dynamic>;
  _items = decoded
      .map((e) => LibraryItem.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
  _loaded = true;
}

List<LibraryItem> get libraryItems => _items;

/// 按分类分组，供词库抽屉使用。
List<LibraryGroup> getLibraryGroups() {
  final map = <String, List<LibraryItem>>{};
  for (final item in _items) {
    map.putIfAbsent(item.category, () => <LibraryItem>[]).add(item);
  }
  return map.entries
      .map((e) => LibraryGroup(category: e.key, items: e.value))
      .toList();
}

/// 按 entry id 查内置词表。
LibraryItem? getLibraryItemById(String id) {
  for (final item in _items) {
    if (item.entry.id == id) return item;
  }
  return null;
}
