import 'package:flutter/material.dart';

import '../services/credits.dart';
import '../services/ocr.dart';
import '../services/ocr_config.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_icons.dart';

/// 识别模型设置：免费 / 高级 / 自定义（BYOK）三档。
///
/// 对应 RN 版 src/components/OcrSettingsModal.tsx。
enum _ViewMode { free, premium, custom }

/// 用户在弹窗里做出的选择。
sealed class OcrSettingsResult {
  const OcrSettingsResult();
}

/// 保存/清除自定义配置（null 表示清除，回落到内置服务）。
class OcrSettingsSaveCustom extends OcrSettingsResult {
  const OcrSettingsSaveCustom(this.config);

  final OcrProviderConfig? config;
}

/// 选用某个内置模型（会清掉自定义配置，让内置服务生效）。
class OcrSettingsSelectModel extends OcrSettingsResult {
  const OcrSettingsSelectModel(this.modelId);

  final String modelId;
}

/// 请求打开充值流程。
class OcrSettingsOpenRecharge extends OcrSettingsResult {
  const OcrSettingsOpenRecharge();
}

final BuiltinModel _freeModel =
    kBuiltinModels.firstWhere((m) => m.tier == ModelTier.free);
final BuiltinModel _premiumModel =
    kBuiltinModels.firstWhere((m) => m.tier == ModelTier.premium);

Future<OcrSettingsResult?> showOcrSettingsModal(
  BuildContext context, {
  required OcrProviderConfig? value,
  required int credits,
}) {
  return showDialog<OcrSettingsResult>(
    context: context,
    barrierColor: context.themeController.colors.overlay,
    builder: (dialogContext) =>
        _OcrSettingsModal(value: value, credits: credits),
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

class _OcrSettingsModal extends StatefulWidget {
  const _OcrSettingsModal({required this.value, required this.credits});

  final OcrProviderConfig? value;
  final int credits;

  @override
  State<_OcrSettingsModal> createState() => _OcrSettingsModalState();
}

class _OcrSettingsModalState extends State<_OcrSettingsModal> {
  final bool _webRequiresKey = requiresCustomOcrConfig();

  late final TextEditingController _baseUrlController =
      TextEditingController(text: widget.value?.baseUrl ?? '');
  late final TextEditingController _apiKeyController =
      TextEditingController(text: widget.value?.apiKey ?? '');
  late final TextEditingController _modelController =
      TextEditingController(text: widget.value?.model ?? '');

  _ViewMode _view = _ViewMode.free;
  bool _showKey = false;
  _TestState _test = const _TestIdle();

  @override
  void initState() {
    super.initState();
    // 打开时同步表单与当前生效的档位。
    if (_webRequiresKey || isCustomOcrConfigSet(widget.value)) {
      _view = _ViewMode.custom;
    } else {
      loadSelectedModelId().then((id) {
        if (!mounted) return;
        setState(() {
          _view = isPremiumModel(id) ? _ViewMode.premium : _ViewMode.free;
        });
      });
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _baseUrlController.text.trim().isNotEmpty &&
      _modelController.text.trim().isNotEmpty &&
      _apiKeyController.text.trim().isNotEmpty;

  void _applyPreset(OcrProviderPreset preset) {
    setState(() {
      _baseUrlController.text = preset.baseUrl;
      _modelController.text = preset.model;
      _test = const _TestIdle();
    });
  }

  void _handleSave() {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      OcrSettingsSaveCustom(
        OcrProviderConfig(
          baseUrl: _baseUrlController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
          model: _modelController.text.trim(),
        ),
      ),
    );
  }

  void _handleClear() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(const OcrSettingsSaveCustom(null));
  }

  Future<void> _handleTest() async {
    if (!_canSave) return;
    setState(() => _test = const _TestTesting());
    try {
      await testOcrConfig(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
      );
      if (mounted) setState(() => _test = const _TestOk());
    } catch (e) {
      if (mounted) {
        setState(() => _test = _TestError(_errorMessage(e)));
      }
    }
  }

  String _errorMessage(Object e) {
    final text = e is Exception ? e.toString() : '测试失败';
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  String get _statusLine {
    if (isCustomOcrConfigSet(widget.value)) return '当前使用自定义服务配置';
    if (_webRequiresKey) return '尚未配置 — Web 版需自备 API Key';
    if (_view == _ViewMode.premium) {
      return '当前使用高级模型 · 余额 ${widget.credits}';
    }
    return '当前使用免费模型';
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
                    // 档位选择 —— Web 上没有内置 key，隐藏免费/高级。
                    if (!_webRequiresKey)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: Spacing.xs,
                        ),
                        child: Row(
                          children: [
                            _tierChip('免费', _ViewMode.free, colors),
                            const SizedBox(width: Spacing.xs),
                            _tierChip('高级', _ViewMode.premium, colors),
                            const SizedBox(width: Spacing.xs),
                            _tierChip('自定义', _ViewMode.custom, colors),
                          ],
                        ),
                      ),
                    if (_view == _ViewMode.free)
                      _ModelInfoCard(
                        model: _freeModel,
                        badge: '免费',
                        badgeColor: colors.secondary,
                        badgeBg: colors.surface,
                        costText: '无限次使用',
                      ),
                    if (_view == _ViewMode.premium) ..._buildPremium(colors),
                    if (_view == _ViewMode.custom) ..._buildCustom(colors),
                    const SizedBox(height: Spacing.md),
                    _disclaimer(colors),
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
            '识别模型',
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

  Widget _tierChip(String label, _ViewMode mode, AppColors colors) {
    final active = _view == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _view = mode),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm + 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.primarySoft : colors.surface,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: active ? colors.primary : colors.border,
              width: 1.5,
            ),
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
    );
  }

  List<Widget> _buildPremium(AppColors colors) {
    return [
      _ModelInfoCard(
        model: _premiumModel,
        badge: '高级',
        badgeColor: colors.gold,
        badgeBg: colors.goldSoft,
        costText: '每次识别扣除 ${_premiumModel.creditCost} credit',
      ),
      Container(
        margin: const EdgeInsets.only(top: Spacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: colors.primarySoft,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: colors.primary),
        ),
        child: Row(
          children: [
            Icon(AppIcons.wallet, size: 16, color: colors.primary),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                '余额 ${widget.credits} credits',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
            GestureDetector(
              onTap: () =>
                  Navigator.of(context).pop(const OcrSettingsOpenRecharge()),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
                child: Text(
                  '充值',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.background,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (widget.credits < _premiumModel.creditCost)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: Spacing.xs),
          child: Text(
            '余额不足，充值后可使用高级识别',
            style: TextStyle(fontSize: 11, color: colors.danger),
          ),
        ),
    ];
  }

  List<Widget> _buildCustom(AppColors colors) {
    final usingCustom = isCustomOcrConfigSet(widget.value);

    return [
      if (_webRequiresKey && !usingCustom)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: Spacing.xs),
          child: Text(
            '听写与词库不需要 Key；仅拍照识别需要。请选择下方服务商并填写密钥。',
            style: TextStyle(fontSize: 11, color: colors.subtle),
          ),
        ),
      _fieldLabel('服务商预设', colors),
      Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          for (final preset in kOcrProviderPresets)
            _presetChip(preset, colors),
        ],
      ),
      _fieldLabel('接口地址 (Base URL)', colors),
      _textField(
        controller: _baseUrlController,
        hint: 'https://api.example.com/v1',
        keyboardType: TextInputType.url,
        colors: colors,
      ),
      _hint('将自动拼接 /chat/completions，也可直接粘贴完整地址', colors),
      _fieldLabel('API Key', colors),
      _textField(
        controller: _apiKeyController,
        hint: 'sk-...',
        obscure: !_showKey,
        colors: colors,
        suffix: Semantics(
          button: true,
          label: _showKey ? '隐藏密钥' : '显示密钥',
          child: GestureDetector(
            onTap: () => setState(() => _showKey = !_showKey),
            behavior: HitTestBehavior.opaque,
            child: Icon(
              _showKey ? AppIcons.eyeOffOutline : AppIcons.eyeOutline,
              size: 20,
              color: colors.subtle,
            ),
          ),
        ),
      ),
      _fieldLabel('模型名称', colors),
      _textField(
        controller: _modelController,
        hint: '例如 gpt-4o-mini',
        colors: colors,
      ),
      _hint('请填写支持图像识别的视觉模型', colors),
      if (_test is _TestOk)
        _testResult(
          icon: AppIcons.checkmarkCircle,
          iconColor: colors.primary,
          text: '连接成功，配置可用',
          textColor: colors.primary,
          background: colors.dangerSoft,
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
          onTap: (_canSave && _test is! _TestTesting) ? _handleTest : null,
          behavior: HitTestBehavior.opaque,
          child: Opacity(
            opacity: _canSave ? 1 : 0.4,
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: colors.border),
              ),
              child: _test is _TestTesting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.foreground,
                      ),
                    )
                  : Text(
                      '测试连接',
                      style: TextStyle(
                        fontSize: 14,
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

  Widget _presetChip(OcrProviderPreset preset, AppColors colors) {
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
        child: Text(
          preset.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? colors.primary : colors.foreground,
          ),
        ),
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
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: suffix != null ? Spacing.md : Spacing.md,
      ),
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

  Widget _disclaimer(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: colors.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(AppIcons.infoOutline, size: 14, color: colors.subtle),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              kOcrDisclaimer,
              style: TextStyle(fontSize: 11, color: colors.subtle),
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
      child: _view == _ViewMode.custom
          ? Row(
              children: [
                Expanded(
                  child: _footerButton(
                    label: _webRequiresKey ? '清除配置' : '恢复默认',
                    textColor: colors.muted,
                    borderColor: colors.border,
                    onTap: _handleClear,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Opacity(
                    opacity: _canSave ? 1 : 0.4,
                    child: _footerButton(
                      label: '保存',
                      textColor: colors.background,
                      backgroundColor: colors.primary,
                      onTap: _canSave ? _handleSave : null,
                    ),
                  ),
                ),
              ],
            )
          : _footerButton(
              label: '使用此模型',
              textColor: colors.background,
              backgroundColor: colors.primary,
              onTap: () => Navigator.of(context).pop(
                OcrSettingsSelectModel(
                  _view == _ViewMode.premium
                      ? _premiumModel.id
                      : _freeModel.id,
                ),
              ),
            ),
    );
  }

  Widget _footerButton({
    required String label,
    required Color textColor,
    required VoidCallback? onTap,
    Color? backgroundColor,
    Color? borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(Radii.button),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 1.5)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _ModelInfoCard extends StatelessWidget {
  const _ModelInfoCard({
    required this.model,
    required this.badge,
    required this.badgeColor,
    required this.badgeBg,
    required this.costText,
  });

  final BuiltinModel model;
  final String badge;
  final Color badgeColor;
  final Color badgeBg;
  final String costText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.only(top: Spacing.xs),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.surface),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                model.label,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 17,
                  color: colors.foreground,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            model.description,
            style: TextStyle(fontSize: 13, color: colors.muted),
          ),
          const SizedBox(height: Spacing.xs + 2),
          Row(
            children: [
              Icon(AppIcons.pricetag, size: 14, color: colors.subtle),
              const SizedBox(width: 4),
              Text(
                costText,
                style: TextStyle(fontSize: 12, color: colors.subtle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
