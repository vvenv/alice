import 'package:flutter/material.dart';

import '../services/tts.dart'
    show isEdgeTtsSupported, testEdgeVoices, testTtsConfig;
import '../services/tts_config.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_icons.dart';

/// 发音源设置：微软 Edge / 有道词典发音 / 自定义 OpenAI 兼容 TTS 接口。
///
/// 对应 Expo 版 src/components/TtsSettingsModal.tsx。

/// 用户在弹窗里做出的选择。
class TtsSettingsResult {
  const TtsSettingsResult({
    required this.source,
    required this.config,
    required this.edgeVoices,
  });

  final TtsSource source;

  /// 自定义配置；选别的源时保持原样不动。
  final TtsProviderConfig? config;

  /// Edge 音色；同样只在选中时才会变。
  final EdgeVoiceConfig edgeVoices;
}

Future<TtsSettingsResult?> showTtsSettingsModal(
  BuildContext context, {
  required TtsSource source,
  required TtsProviderConfig? config,
  required EdgeVoiceConfig edgeVoices,
}) {
  return showDialog<TtsSettingsResult>(
    context: context,
    barrierColor: context.themeController.colors.overlay,
    builder: (_) => _TtsSettingsModal(
      source: source,
      config: config,
      edgeVoices: edgeVoices,
    ),
  );
}

sealed class _TestState {
  const _TestState();
}

class _TestIdle extends _TestState {
  const _TestIdle();
}

class _TestTesting extends _TestState {
  const _TestTesting();
}

class _TestOk extends _TestState {
  const _TestOk();
}

class _TestError extends _TestState {
  const _TestError(this.message);

  final String message;
}

class _TtsSettingsModal extends StatefulWidget {
  const _TtsSettingsModal({
    required this.source,
    required this.config,
    required this.edgeVoices,
  });

  final TtsSource source;
  final TtsProviderConfig? config;
  final EdgeVoiceConfig edgeVoices;

  @override
  State<_TtsSettingsModal> createState() => _TtsSettingsModalState();
}

class _TtsSettingsModalState extends State<_TtsSettingsModal> {
  late TtsSource _source = widget.source;
  late EdgeVoiceConfig _edgeVoices = widget.edgeVoices;
  late TtsApiKind _api = widget.config?.api ?? TtsApiKind.speech;
  late final TextEditingController _baseUrlController =
      TextEditingController(text: widget.config?.baseUrl ?? '');
  late final TextEditingController _apiKeyController =
      TextEditingController(text: widget.config?.apiKey ?? '');
  late final TextEditingController _modelController =
      TextEditingController(text: widget.config?.model ?? '');
  late final TextEditingController _voiceEnController =
      TextEditingController(text: widget.config?.voiceEn ?? '');
  late final TextEditingController _voiceZhController =
      TextEditingController(text: widget.config?.voiceZh ?? '');
  late String? _responseFormat = widget.config?.responseFormat;

  bool _showKey = false;
  _TestState _test = const _TestIdle();

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _voiceEnController.dispose();
    _voiceZhController.dispose();
    super.dispose();
  }

  TtsProviderConfig get _draft => TtsProviderConfig(
        api: _api,
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
        voiceEn: _voiceEnController.text.trim(),
        voiceZh: _voiceZhController.text.trim(),
        responseFormat: _responseFormat,
      );

  bool get _canSave =>
      _source != TtsSource.custom || isTtsProviderConfigSet(_draft);

  String get _statusLine => switch (widget.source) {
        TtsSource.edge => '当前使用微软 Edge 发音',
        TtsSource.youdao => '当前使用有道词典发音',
        TtsSource.custom => isTtsProviderConfigSet(widget.config)
            ? '当前使用自定义发音服务'
            : '保存后启用自定义发音',
      };

  void _applyPreset(TtsProviderPreset preset) {
    setState(() {
      _api = preset.api;
      _baseUrlController.text = preset.baseUrl;
      _modelController.text = preset.model;
      _voiceEnController.text = preset.voiceEn;
      _voiceZhController.text = preset.voiceZh;
      _responseFormat = preset.responseFormat;
      _test = const _TestIdle();
    });
  }

  void _handleSave() {
    Navigator.of(context).pop(
      TtsSettingsResult(
        source: _source,
        // 切走时不要抹掉已填好的自定义配置 —— 用户多半只是想临时换一下。
        config: _source == TtsSource.custom ? _draft : widget.config,
        edgeVoices: _edgeVoices,
      ),
    );
  }

  Future<void> _handleEdgeTest() async {
    setState(() => _test = const _TestTesting());
    try {
      await testEdgeVoices(_edgeVoices);
      if (mounted) setState(() => _test = const _TestOk());
    } catch (e) {
      if (mounted) setState(() => _test = _TestError(_errorMessage(e)));
    }
  }

  Future<void> _handleTest() async {
    final cfg = _draft;
    if (!isTtsProviderConfigSet(cfg)) return;

    setState(() => _test = const _TestTesting());
    try {
      await testTtsConfig(cfg);
      if (mounted) setState(() => _test = const _TestOk());
    } catch (e) {
      if (mounted) setState(() => _test = _TestError(_errorMessage(e)));
    }
  }

  static String _errorMessage(Object error) {
    final text = error.toString();
    final message = text.startsWith('Exception: ') ? text.substring(11) : text;
    return message.isEmpty ? '试听失败' : message;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(Spacing.lg),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxWidth: 380, maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colors),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: Spacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.xs),
                      child: Text(
                        _statusLine,
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: Spacing.xs),
                      child: Row(
                        children: [
                          _sourceChip('微软 Edge', TtsSource.edge, colors),
                          const SizedBox(width: Spacing.xs),
                          _sourceChip('有道词典', TtsSource.youdao, colors),
                          const SizedBox(width: Spacing.xs),
                          _sourceChip('自定义接口', TtsSource.custom, colors),
                        ],
                      ),
                    ),
                    if (_source == TtsSource.edge) ..._buildEdge(colors),
                    if (_source == TtsSource.youdao)
                      _infoCard(
                        colors,
                        '使用有道词典免费单词发音，首次播放后本地缓存；'
                        '中文释义与未缓存的词由系统 TTS 朗读。',
                      ),
                    if (_source == TtsSource.custom) ..._buildCustom(colors),
                  ],
                ),
              ),
            ),
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEdge(AppColors colors) {
    if (!isEdgeTtsSupported()) {
      return [
        _infoCard(
          colors,
          '当前平台（网页版）用不了 Edge 发音，会自动回落到有道 / 系统 TTS。'
          '手机与桌面版可用。',
        ),
      ];
    }
    return [
      _infoCard(
        colors,
        '微软 Edge 浏览器的朗读服务：免费、不用注册，中英文都自然，'
        '生成后本地缓存。接口非官方公开，失败时自动回落有道 / 系统 TTS。',
      ),
      _fieldLabel('英文音色', colors),
      Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          for (final voice in kEdgeVoicesEn)
            _voiceChip(
              voice,
              active: _edgeVoices.en == voice.name,
              colors: colors,
              onTap: () => setState(() {
                _edgeVoices = _edgeVoices.copyWith(en: voice.name);
                _test = const _TestIdle();
              }),
            ),
        ],
      ),
      _fieldLabel('中文音色', colors),
      Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          for (final voice in kEdgeVoicesZh)
            _voiceChip(
              voice,
              active: _edgeVoices.zh == voice.name,
              colors: colors,
              onTap: () => setState(() {
                _edgeVoices = _edgeVoices.copyWith(zh: voice.name);
                _test = const _TestIdle();
              }),
            ),
        ],
      ),
      _hint('中文音色用于朗读释义；换音色后已缓存的发音会重新生成。', colors),
      ..._testWidgets(colors, enabled: true, run: _handleEdgeTest),
    ];
  }

  List<Widget> _buildCustom(AppColors colors) {
    return [
      _infoCard(
        colors,
        '可使用 OpenAI 兼容的大模型 TTS（如小米 MiMo，限时免费），发音更自然；'
        '接口失败或离线时自动回落系统 TTS。',
      ),
      _fieldLabel('服务商', colors),
      Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          for (final preset in kTtsProviderPresets) _presetChip(preset, colors),
        ],
      ),
      _fieldLabel('接口类型', colors),
      Row(
        children: [
          _apiChip('Audio Speech', TtsApiKind.speech, colors),
          const SizedBox(width: Spacing.xs),
          _apiChip('Chat Completions', TtsApiKind.chat, colors),
        ],
      ),
      _hint(
        '标准 /audio/speech 接口选 Audio Speech；经对话接口合成选 Chat Completions。',
        colors,
      ),
      _fieldLabel('接口地址 (Base URL)', colors),
      _textField(
        controller: _baseUrlController,
        hint: 'https://api.example.com/v1',
        colors: colors,
        keyboardType: TextInputType.url,
      ),
      _fieldLabel('API Key', colors),
      _textField(
        controller: _apiKeyController,
        hint: 'sk-...',
        colors: colors,
        obscure: !_showKey,
        suffix: Semantics(
          button: true,
          label: _showKey ? '隐藏密钥' : '显示密钥',
          child: GestureDetector(
            onTap: () => setState(() => _showKey = !_showKey),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: Spacing.sm),
              child: Icon(
                _showKey ? AppIcons.eyeOff : AppIcons.eye,
                size: 18,
                color: colors.muted,
              ),
            ),
          ),
        ),
      ),
      _fieldLabel('模型名称', colors),
      _textField(
        controller: _modelController,
        hint: '例如 mimo-v2.5-tts',
        colors: colors,
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldLabel('英文音色', colors),
                _textField(
                  controller: _voiceEnController,
                  hint: '默认',
                  colors: colors,
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldLabel('中文音色', colors),
                _textField(
                  controller: _voiceZhController,
                  hint: '默认',
                  colors: colors,
                ),
              ],
            ),
          ),
        ],
      ),
      _hint('留空使用服务商默认音色；修改音色或语速后会重新生成发音。', colors),
      ..._testWidgets(
        colors,
        enabled: isTtsProviderConfigSet(_draft),
        run: _handleTest,
      ),
    ];
  }

  /// 试听按钮 + 结果提示。Edge 与自定义接口共用。
  List<Widget> _testWidgets(
    AppColors colors, {
    required bool enabled,
    required Future<void> Function() run,
  }) {
    return [
      if (_test is _TestOk)
        _testResult(
          icon: AppIcons.checkmarkCircle,
          iconColor: colors.primary,
          text: '连接成功，已播放试听',
          textColor: colors.primary,
          background: colors.primarySoft,
        ),
      if (_test is _TestError)
        _testResult(
          icon: AppIcons.alertCircle,
          iconColor: colors.danger,
          text: (_test as _TestError).message,
          textColor: colors.danger,
          background: colors.dangerSoft,
        ),
      Padding(
        padding: const EdgeInsets.only(top: Spacing.sm),
        child: GestureDetector(
          onTap: (enabled && _test is! _TestTesting) ? run : null,
          behavior: HitTestBehavior.opaque,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                _test is _TestTesting ? '试听中…' : '试听',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _voiceChip(
    EdgeVoiceOption voice, {
    required bool active,
    required AppColors colors,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: active,
      label: voice.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm + 2,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: active ? colors.primarySoft : colors.surface,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: active ? colors.primary : colors.border),
          ),
          child: Text(
            voice.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? colors.primary : colors.foreground,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '发音源',
            style: TextStyle(
              fontFamily: AppFonts.displayZh,
              fontSize: 17,
              color: colors.foreground,
            ),
          ),
          Semantics(
            button: true,
            label: '关闭',
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Icon(AppIcons.close, size: 22, color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(AppColors colors) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: Opacity(
        opacity: _canSave ? 1 : 0.4,
        child: GestureDetector(
          onTap: _canSave ? _handleSave : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: Text(
              '保存',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.background,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceChip(String label, TtsSource source, AppColors colors) {
    final active = _source == source;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          onTap: () => setState(() => _source = source),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm + 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? colors.primarySoft : colors.surface,
              borderRadius: BorderRadius.circular(Radii.control),
              border:
                  Border.all(color: active ? colors.primary : colors.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? colors.primary : colors.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _apiChip(String label, TtsApiKind api, AppColors colors) {
    final active = _api == api;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _api = api;
          _test = const _TestIdle();
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.primarySoft : colors.surface,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: active ? colors.primary : colors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? colors.primary : colors.foreground,
            ),
          ),
        ),
      ),
    );
  }

  Widget _presetChip(TtsProviderPreset preset, AppColors colors) {
    final active = preset.baseUrl.isNotEmpty &&
        preset.baseUrl == _baseUrlController.text.trim() &&
        preset.model == _modelController.text.trim();

    return GestureDetector(
      onTap: () => _applyPreset(preset),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm + 2,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: active ? colors.primarySoft : colors.surface,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: active ? colors.primary : colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preset.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? colors.primary : colors.foreground,
              ),
            ),
            if (preset.hint != null)
              Text(
                preset.hint!,
                style: TextStyle(fontSize: 10, color: colors.subtle),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(AppColors colors, String text) {
    return Container(
      margin: const EdgeInsets.only(top: Spacing.xs, bottom: Spacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: colors.borderSubtle, width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, height: 1.5, color: colors.muted),
      ),
    );
  }

  Widget _fieldLabel(String label, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xs),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.subtle,
        ),
      ),
    );
  }

  Widget _hint(String text, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: Spacing.xs),
      child: Text(text, style: TextStyle(fontSize: 11, color: colors.subtle)),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required AppColors colors,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => setState(() => _test = const _TestIdle()),
              keyboardType: keyboardType,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              style: TextStyle(fontSize: 14, color: colors.foreground),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: colors.subtle),
              ),
            ),
          ),
          if (suffix != null) suffix,
        ],
      ),
    );
  }

  Widget _testResult({
    required IconData icon,
    required Color iconColor,
    required String text,
    required Color textColor,
    required Color background,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: Spacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
