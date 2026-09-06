import 'dart:io';

import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/services/sound.dart';
import 'package:alice_dictation/services/storage.dart';
import 'package:alice_dictation/services/tts.dart';
import 'package:alice_dictation/services/tts_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置项的持久化与序列化。
///
/// 这些值都要跨启动活下来，也都要能从 Expo 版的老沙箱搬过来。手写的
/// toJson/fromJson 和「新增 key 忘了登记进迁移清单」是这一块最容易出的两种错。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
  });

  group('数值设置会被夹进合法区间并原样读回', () {
    test('语速', () async {
      await saveSpeechRate(1.2);
      expect(await loadSpeechRate(), closeTo(1.2, 0.001));

      await saveSpeechRate(99);
      expect(await loadSpeechRate(), lessThanOrEqualTo(kMaxSpeechRate));

      await saveSpeechRate(-5);
      expect(await loadSpeechRate(), greaterThanOrEqualTo(kMinSpeechRate));
    });

    test('听写间隔', () async {
      await saveIntervalSec(5.5);
      expect(await loadIntervalSec(), closeTo(5.5, 0.001));

      await saveIntervalSec(9999);
      expect(await loadIntervalSec(), lessThanOrEqualTo(kMaxIntervalSec));

      await saveIntervalSec(0);
      expect(await loadIntervalSec(), greaterThanOrEqualTo(kMinIntervalSec));
    });
  });

  test('提示音开关能读回', () async {
    setSoundEnabled(false);
    expect(await loadSoundEnabled(), isFalse);

    setSoundEnabled(true);
    expect(await loadSoundEnabled(), isTrue);
  });

  test('「朗读中文释义」开关能读回，同步读也跟着变', () async {
    setReadTranslationEnabled(true);
    expect(isReadTranslationEnabled(), isTrue);
    expect(await loadReadTranslation(), isTrue);

    setReadTranslationEnabled(false);
    expect(isReadTranslationEnabled(), isFalse);
  });

  group('发音源配置', () {
    test('来源能读回', () async {
      await saveTtsSource(TtsSource.custom);
      expect((await loadTtsSettings()).source, TtsSource.custom);

      await saveTtsSource(TtsSource.youdao);
      expect((await loadTtsSettings()).source, TtsSource.youdao);

      await saveTtsSource(TtsSource.edge);
      expect((await loadTtsSettings()).source, TtsSource.edge);
    });

    test('从没选过时是 Edge —— 免费、免配置，所以是默认', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await Prefs.init();

      final settings = await loadTtsSettings();
      expect(settings.source, TtsSource.edge);
      expect(settings.edgeVoices.en, kDefaultEdgeVoiceEn);
      expect(settings.edgeVoices.zh, kDefaultEdgeVoiceZh);
    });

    test('Edge 音色能读回，坏值回落到默认音色', () async {
      await saveEdgeVoices(
        const EdgeVoiceConfig(en: 'en-GB-SoniaNeural', zh: 'zh-CN-YunxiNeural'),
      );
      final back = (await loadTtsSettings()).edgeVoices;
      expect(back.en, 'en-GB-SoniaNeural');
      expect(back.zh, 'zh-CN-YunxiNeural');

      // 空音色会让 SSML 里的 voice name 为空，服务端直接报错 —— 挡在这里。
      expect(
        EdgeVoiceConfig.fromJson(const {'en': '  ', 'zh': 42}).en,
        kDefaultEdgeVoiceEn,
      );
      expect(
        EdgeVoiceConfig.fromJson(const {'en': '  ', 'zh': 42}).zh,
        kDefaultEdgeVoiceZh,
      );
    });

    test('服务商配置逐字段往返', () async {
      const cfg = TtsProviderConfig(
        api: TtsApiKind.chat,
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-secret',
        model: 'some-tts',
        voiceEn: 'alex',
        voiceZh: '冰糖',
        responseFormat: 'wav',
      );

      await saveTtsProviderConfig(cfg);
      final back = (await loadTtsSettings()).config;

      expect(back, isNotNull);
      expect(back!.api, TtsApiKind.chat);
      expect(back.baseUrl, cfg.baseUrl);
      expect(back.apiKey, cfg.apiKey);
      expect(back.model, cfg.model);
      expect(back.voiceEn, cfg.voiceEn);
      expect(back.voiceZh, cfg.voiceZh);
      expect(back.responseFormat, 'wav');
    });

    test('没有 responseFormat 的配置也能往返', () async {
      const cfg = TtsProviderConfig(
        api: TtsApiKind.speech,
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: 'm',
      );

      await saveTtsProviderConfig(cfg);
      final back = (await loadTtsSettings()).config;

      expect(back, isNotNull);
      expect(back!.responseFormat, isNull);
      expect(back.voiceEn, '');
    });

    test('清除配置后读回是 null', () async {
      await saveTtsProviderConfig(
        const TtsProviderConfig(
          api: TtsApiKind.speech,
          baseUrl: 'u',
          apiKey: 'k',
          model: 'm',
        ),
      );
      await saveTtsProviderConfig(null);

      expect((await loadTtsSettings()).config, isNull);
    });

    test('三样必填齐了才算可用', () {
      expect(isTtsProviderConfigSet(null), isFalse);
      expect(
        isTtsProviderConfigSet(const TtsProviderConfig(
          api: TtsApiKind.speech,
          baseUrl: '  ',
          apiKey: 'k',
          model: 'm',
        )),
        isFalse,
      );
      expect(
        isTtsProviderConfigSet(const TtsProviderConfig(
          api: TtsApiKind.speech,
          baseUrl: 'u',
          apiKey: '',
          model: 'm',
        )),
        isFalse,
      );
      expect(
        isTtsProviderConfigSet(const TtsProviderConfig(
          api: TtsApiKind.speech,
          baseUrl: 'u',
          apiKey: 'k',
          model: 'm',
        )),
        isTrue,
      );
    });

    test('buildSpeechUrl 会补路径，也容忍已经贴了完整地址', () {
      expect(
        buildSpeechUrl('https://api.example.com/v1'),
        'https://api.example.com/v1/audio/speech',
      );
      expect(
        buildSpeechUrl('https://api.example.com/v1/'),
        'https://api.example.com/v1/audio/speech',
      );
      expect(
        buildSpeechUrl('  https://api.example.com/v1//  '),
        'https://api.example.com/v1/audio/speech',
      );
      expect(
        buildSpeechUrl('https://api.example.com/v1/audio/speech'),
        'https://api.example.com/v1/audio/speech',
      );
    });

    test('每个预设都是自洽的', () {
      for (final preset in kTtsProviderPresets) {
        expect(preset.id, isNotEmpty);
        expect(preset.label, isNotEmpty);
        if (preset.id == 'custom') continue;
        expect(preset.baseUrl, startsWith('https://'),
            reason: '${preset.id} 的 baseUrl 应该是 https');
        expect(preset.model, isNotEmpty, reason: '${preset.id} 缺 model');
      }
    });
  });

  // 这条盯的是一类反复出现的疏忽：新加了一个持久化 key，却忘了把它登记进
  // legacy_migration_io.dart 的迁移清单 —— 结果从 Expo 版升上来的用户，
  // 那个设置会被悄悄重置成默认值。没有别的机制能发现它。
  test('每个持久化 key 都登记进了老数据迁移清单', () {
    final migration =
        File('lib/services/legacy_migration_io.dart').readAsStringSync();
    final declared = RegExp(r"'((?:alice|dictation)_[a-z_]+)'")
        .allMatches(migration)
        .map((m) => m.group(1)!)
        .toSet();

    final used = <String, String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('legacy_migration')) continue;
      for (final m in RegExp(r"'((?:alice|dictation)_[a-z_]+)'")
          .allMatches(entity.readAsStringSync())) {
        used[m.group(1)!] = entity.path;
      }
    }

    expect(used, isNotEmpty, reason: '一个 key 都没扫到，正则大概是坏的');

    // Flutter 版之后才加的 key。RN 版从来没写过，也就没有东西可搬 ——
    // 放进 _legacyKeys 反而会让那份「RN 版写过的全部 key」的清单说谎。
    // 新增条目前先确认一遍：RN 版真的没写过这个 key 吗？
    const flutterOnly = <String>{
      'alice_camera_button_pos', // 拍照按钮拖到哪儿了，RN 版的按钮不能拖
      'alice_tts_edge_voices', // Edge 发音是 Flutter 版才有的
    };

    final missing = <String>[];
    used.forEach((key, path) {
      if (flutterOnly.contains(key)) return;
      if (!declared.contains(key)) missing.add('$key（$path）');
    });

    expect(
      missing,
      isEmpty,
      reason: '这些 key 没进 legacy_migration_io.dart 的迁移清单，'
          '老用户升级后对应设置会丢：\n  ${missing.join('\n  ')}',
    );
  });
}
