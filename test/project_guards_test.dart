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
        final webp = File('android/app/src/main/res/mipmap-$d/ic_launcher.webp');
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

  group('Android 清单', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    // 0.6.2 就栽在这里：manifest 声明的类不存在，R8 把它当死代码删了，
    // 编译期毫无征兆，装上必闪退。
    test('声明的启动 Activity 在 Kotlin 源码里真的存在', () {
      final gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
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
        expect(manifest, contains('android.permission.$p'),
            reason: '缺权限 $p');
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
      for (final m
          in RegExp(r'^\s+- (assets/[^\s]+)$', multiLine: true).allMatches(pubspec)) {
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
}
