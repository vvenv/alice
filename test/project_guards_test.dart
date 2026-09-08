import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 仓库级的不变量。
///
/// 这些不是「代码逻辑」，而是构建产物的属性 —— 全都真的出过事，而且全都在
/// 编译期毫无征兆，只有装到手机上才看得出来。放在这里，改坏了立刻红。
void main() {
  const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

  group('应用图标', () {
    // 0.6.3 之前发出去的包用的是 flutter create 铺的蓝色 F。
    test('五个密度的图标都在，而且不是 Flutter 默认图标', () {
      for (final d in densities) {
        final webp =
            File('android/app/src/main/res/mipmap-$d/ic_launcher.webp');
        expect(webp.existsSync(), isTrue,
            reason: 'mipmap-$d/ic_launcher.webp 不见了，'
                '跑一次 pnpm icons:build');

        // flutter create 铺的是 .png；和我们的 .webp 同名会撞 duplicate
        // resource，而且它就是那个蓝色 F。
        final png = File('android/app/src/main/res/mipmap-$d/ic_launcher.png');
        expect(png.existsSync(), isFalse,
            reason: 'mipmap-$d 下混进了 Flutter 默认的 ic_launcher.png');
      }
    });

    test('自适应图标与圆形图标齐全', () {
      for (final d in densities) {
        for (final name in ['ic_launcher_round', 'ic_launcher_foreground']) {
          expect(
            File('android/app/src/main/res/mipmap-$d/$name.webp').existsSync(),
            isTrue,
            reason: 'mipmap-$d/$name.webp 不见了',
          );
        }
      }
      expect(
        File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
            .existsSync(),
        isTrue,
      );
      expect(
        File('android/app/src/main/res/values/colors.xml').existsSync(),
        isTrue,
        reason: '自适应图标的 iconBackground 颜色定义不见了',
      );
    });

    test('图标源文件还在，能重新生成', () {
      for (final name in [
        'icon.png',
        'icon.svg',
        'adaptive-icon.png',
        'adaptive-icon.svg'
      ]) {
        expect(File('assets/icons/$name').existsSync(), isTrue,
            reason: 'assets/icons/$name 不见了');
      }
    });
  });

  // 听写页有一套横屏双栏布局（width >= 700 且宽大于高），iOS / Android
  // 两边也都允许横屏 —— PWA 若锁死竖屏，装到桌面的用户永远看不到它。
  test('Web manifest 不锁死竖屏', () {
    final manifest = File('web/manifest.json').readAsStringSync();
    expect(manifest, isNot(contains('portrait')),
        reason: 'web/manifest.json 锁了竖屏，和听写页的横屏布局对不上');
  });

  group('Android 清单', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    // 0.6.2 就栽在这里：manifest 声明的类不存在，R8 把它当死代码删了，
    // 编译期毫无征兆，装上必闪退。
    test('声明的启动 Activity 在 Kotlin 源码里真的存在', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final namespace =
          RegExp(r'namespace\s*=\s*"([^"]+)"').firstMatch(gradle)?.group(1);
      expect(namespace, isNotNull, reason: 'build.gradle.kts 里读不到 namespace');

      final name = RegExp(r'<activity[^>]*android:name="([^"]+)"', dotAll: true)
          .firstMatch(manifest)
          ?.group(1);
      expect(name, isNotNull, reason: 'manifest 里找不到 <activity>');

      final fqcn = name!.startsWith('.') ? '$namespace$name' : name;
      final path =
          'android/app/src/main/kotlin/${fqcn.replaceAll('.', '/')}.kt';
      expect(File(path).existsSync(), isTrue,
          reason: 'manifest 声明 $fqcn，但 $path 不存在 —— 装到手机上会闪退');

      final pkg = fqcn.substring(0, fqcn.lastIndexOf('.'));
      expect(File(path).readAsStringSync(), contains('package $pkg'),
          reason: '$path 的 package 声明与 $fqcn 对不上');
    });

    test('六个权限齐全', () {
      for (final p in [
        'INTERNET',
        'CAMERA',
        'RECORD_AUDIO',
        'MODIFY_AUDIO_SETTINGS',
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      ]) {
        expect(manifest, contains('android.permission.$p'), reason: '缺权限 $p');
      }
    });

    // Android 11 起没有这条 package visibility 声明，url_launcher 就看不见
    // 浏览器，设置页的「反馈」点了什么也不会发生。
    test('声明了 https 的 VIEW intent，反馈链接才打得开', () {
      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android:scheme="https"'));
    });

    // 「分享到 Alice」这条链路横跨 manifest、Kotlin、Dart 三处，
    // 少哪一处都是「分享菜单里没有 Alice」或者「点了没反应」，编译期无声。
    test('分享意图三处齐全：intent-filter、MainActivity、通道名一致', () {
      expect(manifest, contains('android.intent.action.SEND'),
          reason: 'manifest 少了 SEND 的 intent-filter，分享菜单里不会出现 Alice');
      expect(manifest, contains('android:mimeType="text/plain"'));

      final activity = File(
        'android/app/src/main/kotlin/com/vvenv/alice/MainActivity.kt',
      ).readAsStringSync();
      expect(activity, contains('ACTION_SEND'));
      expect(activity, contains('takeSharedText'));

      final dart =
          File('lib/services/share_intake.dart').readAsStringSync();
      for (final name in ["'alice/share'", 'takeSharedText', 'sharedText']) {
        expect(activity, contains(name.replaceAll("'", '"')),
            reason: 'MainActivity.kt 与 share_intake.dart 的 $name 对不上');
        expect(dart, contains(name),
            reason: 'share_intake.dart 缺 $name');
      }
    });

    test('包名固定为 com.vvenv.alice', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "com.vvenv.alice"'),
          reason: '改了包名就是另一个沙箱，老用户的数据全部读不到');
    });
  });

  group('pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    // 发版脚本按 `x.y.z+code` 解析这一行，格式变了会静默解析出错。
    test('版本号是 x.y.z+versionCode', () {
      final line = RegExp(r'^version:\s*(.+)$', multiLine: true)
          .firstMatch(pubspec)
          ?.group(1)
          ?.trim();
      expect(line, isNotNull);
      expect(RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(line!), isTrue,
          reason: '版本号写成了 "$line"，scripts/lib/version.sh 解析不了');
    });

    test('声明的资源目录都存在', () {
      for (final m in RegExp(r'^\s+- (assets/[^\s]+)$', multiLine: true)
          .allMatches(pubspec)) {
        final path = m.group(1)!;
        final exists = path.endsWith('/')
            ? Directory(path).existsSync()
            : File(path).existsSync();
        expect(exists, isTrue, reason: 'pubspec 声明了 $path，但它不存在');
      }
    });

    test('声明的字体文件都存在', () {
      for (final m
          in RegExp(r'asset:\s*(assets/fonts/[^\s]+)').allMatches(pubspec)) {
        expect(File(m.group(1)!).existsSync(), isTrue,
            reason: '字体 ${m.group(1)} 不存在');
      }
    });
  });

  group('Web 发版', () {
    // 0.7.4 挂到 /app/ 之后，忘了 --base-href，bootstrap / manifest
    // 全打到 alice.edao.plus/ 根路径 404。
    test('发版脚本给 Flutter Web 设了 /app/ 的 base-href', () {
      final script = File('scripts/release-webapp.sh').readAsStringSync();
      expect(script, contains('--base-href /app/'),
          reason: 'Web 挂在 alice.edao.plus/app/，不设 base-href 的话 '
              'flutter_bootstrap.js / manifest.json 会打到官网根路径 404');
      expect(script, contains('replace_web_fonts'),
          reason: 'Web 发版必须把全量思源宋体换成子集，否则首屏约 28MB 字体');
    });

    test('index.html / manifest 不是 Flutter 模板', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, isNot(contains('A new Flutter project.')));
      expect(html, contains('<title>Alice 听写</title>'));
      expect(html, contains('id="app-loading"'));
      expect(html, isNot(contains('#0175C2')));

      final manifest = File('web/manifest.json').readAsStringSync();
      expect(manifest, isNot(contains('alice_dictation')));
      expect(manifest, contains('"name": "Alice 听写"'));
      expect(manifest, contains('#1A2B4A'));
    });

    test('Web 思源宋体子集存在且明显小于全量', () {
      for (final name in [
        'NotoSerifSC_500Medium.ttf',
        'NotoSerifSC_700Bold.ttf',
      ]) {
        final full = File('assets/fonts/$name');
        final subset = File('assets/fonts/web/$name');
        expect(full.existsSync(), isTrue, reason: '全量字体 $name 不见了');
        expect(subset.existsSync(), isTrue,
            reason: 'Web 子集 $name 不见了，跑一次 pnpm fonts:subset');
        expect(
          subset.lengthSync(),
          lessThan(full.lengthSync() * 4 ~/ 10),
          reason: '$name 子集没有明显小于全量（需要 < 40%）',
        );
      }
    });
  });

  group('Android 发版', () {
    test('release.sh 只打并上传 arm64', () {
      final script = File('scripts/release.sh').readAsStringSync();
      expect(script, contains('--split-per-abi'));
      expect(script, contains('--target-platform android-arm64'));
      expect(script, contains('app-arm64-v8a-release.apk'));
    });
  });

  group('Web 兼容', () {
    // 每一条都是 dart2js 照编不误、只有在浏览器里点下去才炸的那种。

    test('lib/ 里没有裸的 dart:io import', () {
      // dart:io 一进 lib/，整个 web 构建直接编译失败。落盘的实现只能藏在
      // `if (dart.library.io)` 条件导入后面（见 tts_cache.dart）。
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('_io.dart')) continue; // 条件导入的原生侧
        if (RegExp(r"^import 'dart:io'", multiLine: true)
            .hasMatch(entity.readAsStringSync())) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '这些文件 import 了 dart:io，web 构建会编译失败：$offenders\n'
              '把实现拆成 xxx_io.dart / xxx_noop.dart，用条件导入挑一个');
    });

    test('OCR 压缩没有无条件走 compressWithFile', () {
      // flutter_image_compress 的 web 实现里 compressWithFile 是
      // `throw UnimplementedError('The method not support web')` ——
      // 编译没问题，浏览器里选完图走到「处理图片中…」就炸。
      final ocr = File('lib/services/ocr.dart').readAsStringSync();
      if (ocr.contains('compressWithFile')) {
        expect(ocr, contains('kIsWeb'),
            reason: 'ocr.dart 用了 compressWithFile，但没有 kIsWeb 分支 —— '
                'Web 上它必抛 UnimplementedError，改用 compressWithList');
        expect(ocr, contains('compressWithList'),
            reason: 'ocr.dart 缺少 Web 侧的 compressWithList 分支');
      }
    });

    test('OCR 入参是 XFile 而不是路径', () {
      // Web 上 XFile.path 是 blob: URL，拿它当文件路径读必然失败。
      final ocr = File('lib/services/ocr.dart').readAsStringSync();
      expect(ocr, contains('Future<XFile?> takePhoto()'),
          reason: 'takePhoto 必须返回 XFile —— Web 上没有真实文件路径');
      expect(ocr, contains('Future<XFile?> pickFromAlbum()'),
          reason: 'pickFromAlbum 必须返回 XFile —— Web 上没有真实文件路径');
    });
  });
}
