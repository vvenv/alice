import 'package:alice_dictation/services/credits.dart';
import 'package:alice_dictation/services/ocr_config.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await saveOcrProviderConfig(null);
  });

  test('未配置且必须自备 OCR 时拦截，不放行去拍照', () async {
    final gate = await canRunOcrNow(customConfigRequired: true);
    expect(gate.allowed, isFalse);
    expect(gate.needsCustomConfig, isTrue);
  });

  test('已配置 BYOK 时即使必须自备 OCR 也放行', () async {
    await saveOcrProviderConfig(
      const OcrProviderConfig(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        model: 'glm-4v-flash',
      ),
    );
    final gate = await canRunOcrNow(customConfigRequired: true);
    expect(gate.allowed, isTrue);
    expect(gate.needsCustomConfig, isFalse);
  });

  test('未注入内置密钥时同样拦截，避免白拍一张', () async {
    final gate = await canRunOcrNow(customConfigRequired: false);
    expect(gate.allowed, isFalse);
    expect(gate.needsCustomConfig, isTrue);
  });
}
