import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'logger.dart';
import 'prefs.dart';

/// 把 RN 版 AsyncStorage 里的数据搬进 shared_preferences。
///
/// 两版的 key 是逐字一致的（`dictation_*` / `alice_*`），但底层存储完全不同：
///
/// - **Android**：AsyncStorage 落在 app 私有目录的 SQLite 库 `RKStorage`，
///   表 `catalystLocalStorage(key TEXT PRIMARY KEY, value TEXT)`。
/// - **iOS**：AsyncStorage 落在 `Documents/RCTAsyncLocalStorage_V1/`，
///   `manifest.json` 存小值；大值在 manifest 里是 null，实际内容放在以
///   key 的 MD5 命名的同目录文件里。
///
/// 迁移只跑一次（用 [_migratedFlagKey] 标记），且**不覆盖**已有值 ——
/// 用户装了 Flutter 版之后产生的新数据永远优先。
///
/// 老数据读不到时静默跳过：全新安装、用户从没用过 RN 版、系统改过目录结构，
/// 都属于正常情况，不该让 App 启动失败。
const _log = Logger('LegacyMigration');

const String _migratedFlagKey = 'alice_legacy_migrated';

/// RN 版写过的全部 key。只搬这些，避免把无关内容带进来。
const List<String> _legacyKeys = [
  'dictation_wrong_words',
  'dictation_word_input',
  'dictation_word_history',
  'dictation_favorites',
  'dictation_speech_rate',
  'dictation_interval_sec',
  'alice_theme_mode',
  'alice_sound_enabled',
  'alice_ocr_credits',
  'alice_ocr_selected_model',
  'alice_ocr_provider_config',
];

/// 执行迁移，返回搬过来的条目数。已经迁过或没有老数据时返回 0。
Future<int> migrateLegacyAsyncStorage() async {
  if (await Prefs.getString(_migratedFlagKey) != null) return 0;

  var migrated = 0;
  try {
    final legacy = await _readLegacyStore();

    for (final key in _legacyKeys) {
      final value = legacy[key];
      if (value == null || value.isEmpty) continue;
      // 不覆盖 Flutter 版自己写过的值。
      if (await Prefs.getString(key) != null) continue;

      await Prefs.setString(key, value);
      migrated += 1;
    }

    if (migrated > 0) {
      _log.info('已迁移 $migrated 条 AsyncStorage 数据');
    }
  } catch (e) {
    // 迁移失败不阻塞启动 —— 最坏结果是用户从空白状态开始。
    _log.warn('迁移老数据失败: $e');
  }

  // 无论成功与否都打标记：失败通常是「压根没有老数据」，
  // 每次启动都重试一遍没有意义。
  await Prefs.setString(_migratedFlagKey, DateTime.now().toIso8601String());
  return migrated;
}

Future<Map<String, String>> _readLegacyStore() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return _readAndroidRkStorage();
    case TargetPlatform.iOS:
      return _readIosAsyncLocalStorage();
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      return const {};
  }
}

// --- Android: SQLite RKStorage --------------------------------------------

Future<Map<String, String>> _readAndroidRkStorage() async {
  final dbDir = await getDatabasesPath();
  final dbPath = '$dbDir/RKStorage';
  if (!File(dbPath).existsSync()) {
    _log.debug('未找到 RKStorage，跳过迁移');
    return const {};
  }

  Database? db;
  try {
    db = await openReadOnlyDatabase(dbPath);
    final rows = await db.query(
      'catalystLocalStorage',
      columns: ['key', 'value'],
    );

    final out = <String, String>{};
    for (final row in rows) {
      final key = row['key'];
      final value = row['value'];
      if (key is String && value is String) out[key] = value;
    }
    return out;
  } finally {
    await db?.close();
  }
}

// --- iOS: RCTAsyncLocalStorage_V1 -----------------------------------------

Future<Map<String, String>> _readIosAsyncLocalStorage() async {
  final documents = await getApplicationDocumentsDirectory();
  final storeDir = Directory('${documents.path}/RCTAsyncLocalStorage_V1');
  final manifestFile = File('${storeDir.path}/manifest.json');
  if (!manifestFile.existsSync()) {
    _log.debug('未找到 RCTAsyncLocalStorage_V1，跳过迁移');
    return const {};
  }

  final manifest =
      json.decode(await manifestFile.readAsString()) as Map<String, dynamic>;

  final out = <String, String>{};
  for (final entry in manifest.entries) {
    final value = entry.value;
    if (value is String) {
      // 小值直接内联在 manifest 里
      out[entry.key] = value;
      continue;
    }
    // manifest 里是 null 表示值存在以 key 的 MD5 命名的独立文件里
    if (value == null) {
      final hashed = md5.convert(utf8.encode(entry.key)).toString();
      final overflow = File('${storeDir.path}/$hashed');
      if (overflow.existsSync()) {
        out[entry.key] = await overflow.readAsString();
      }
    }
  }
  return out;
}
