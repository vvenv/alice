/// 按平台选择老数据迁移实现。
///
/// 只有原生端需要做迁移（Web 版 RN 用的是 localStorage，Flutter Web 的
/// shared_preferences 也落在 localStorage，key 前缀不同但不值得为此迁移）。
library;

export 'legacy_migration_noop.dart'
    if (dart.library.io) 'legacy_migration_io.dart';
