import 'package:shared_preferences/shared_preferences.dart';

/// 键值持久化 —— 对应 RN 版的 AsyncStorage。
///
/// 所有 key 与 RN 版保持字面一致（`dictation_*` / `alice_*`），这样同一台设备上
/// 两个版本读到的是同一组语义字段。
///
/// 注意：key 相同不代表数据能自动带过来 —— RN 的 AsyncStorage 在 Android 上落在
/// 自己的 SQLite 库（RKStorage），iOS 上落在 RCTAsyncLocalStorage 目录，
/// shared_preferences 读不到。老用户的数据迁移见 MIGRATION.md。
class Prefs {
  const Prefs._();

  static SharedPreferences? _instance;

  /// 在 runApp 之前调用一次，之后所有读写都是同步的内存操作 + 异步落盘。
  static Future<void> init() async {
    _instance ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _prefs {
    final p = _instance;
    if (p == null) {
      throw StateError('Prefs.init() 必须在使用前调用');
    }
    return p;
  }

  static Future<String?> getString(String key) async {
    await init();
    return _prefs.getString(key);
  }

  static String? getStringSync(String key) => _prefs.getString(key);

  static Future<void> setString(String key, String value) async {
    await init();
    await _prefs.setString(key, value);
  }

  static Future<void> remove(String key) async {
    await init();
    await _prefs.remove(key);
  }
}
