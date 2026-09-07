import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/credits.dart';
import '../services/haptics.dart';
import '../services/ocr.dart';
import '../services/ocr_config.dart';
import '../services/sound.dart';
import '../services/storage.dart';
import '../services/tts.dart';
import '../services/tts_config.dart';
import '../state/ocr_quota_controller.dart';
import '../state/toast_controller.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/app_slider.dart';
import '../widgets/app_switch.dart';
import '../widgets/ocr_settings_modal.dart';
import '../widgets/tts_settings_modal.dart';
import '../widgets/recharge_modal.dart';

/// 设置页。对应 RN 版 src/screens/SettingsScreen.tsx。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _ready = false;
  bool _soundOn = true;
  bool _hapticsOn = true;
  bool _readTranslationOn = false;
  TtsSource _ttsSource = kDefaultTtsSource;
  EdgeVoiceConfig _edgeVoices = const EdgeVoiceConfig();
  TtsProviderConfig? _ttsConfig;
  double _speechRate = kDefaultSpeechRate;
  double _intervalSec = kDefaultIntervalSec;
  OcrProviderConfig? _customOcrConfig;
  String _appVersion = '—';

  late final ToastController _toast = ToastController();

  OcrQuotaController get _quota => context.read<OcrQuotaController>();

  @override
  void initState() {
    super.initState();
    _toast.addListener(_onToastChanged);
    _bootstrap();
  }

  void _onToastChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final soundOn = await loadSoundEnabled();
    final hapticsOn = await Haptics.load();
    final readTranslation = await loadReadTranslation();
    final tts = await loadTtsSettings();
    final rate = await loadSpeechRate();
    final interval = await loadIntervalSec();
    final custom = await loadOcrProviderConfig();

    setSpeechRate(rate);
    if (!mounted) return;
    setState(() {
      _soundOn = soundOn;
      _hapticsOn = hapticsOn;
      _readTranslationOn = readTranslation;
      _ttsSource = tts.source;
      _edgeVoices = tts.edgeVoices;
      _ttsConfig = tts.config;
      _speechRate = rate;
      _intervalSec = interval;
      _customOcrConfig = custom;
      _ready = true;
    });

    // 版本号走插件，测试环境可能永远完不成；不要挡设置页出现。
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // 忽略
    }
  }

  @override
  void dispose() {
    _toast.removeListener(_onToastChanged);
    _toast.dispose();
    super.dispose();
  }

  // --- 操作 ---------------------------------------------------------------

  void _handleToggleSound(bool value) {
    setState(() => _soundOn = value);
    setSoundEnabled(value);
  }

  void _handleToggleHaptics(bool value) {
    setState(() => _hapticsOn = value);
    Haptics.setEnabled(value);
    // 打开时立刻震一下，让用户知道这个开关管的是什么。
    if (value) Haptics.tapLight();
  }

  void _handleToggleReadTranslation(bool value) {
    setState(() => _readTranslationOn = value);
    setReadTranslationEnabled(value);
  }

  void _handleSpeechRateChanged(double value) {
    final rounded = (value * 10).round() / 10;
    setState(() => _speechRate = rounded);
    setSpeechRate(rounded);
    saveSpeechRate(rounded);
  }

  void _handleIntervalChanged(double value) {
    setState(() => _intervalSec = value);
    saveIntervalSec(value);
  }

  String get _ttsSourceDetail => switch (_ttsSource) {
        TtsSource.edge => '微软 Edge',
        TtsSource.youdao => '有道词典',
        TtsSource.custom =>
          isTtsProviderConfigSet(_ttsConfig) ? '自定义接口' : '未配置',
      };

  Future<void> _openTtsSettings() async {
    final result = await showTtsSettingsModal(
      context,
      source: _ttsSource,
      config: _ttsConfig,
      edgeVoices: _edgeVoices,
    );
    if (!mounted || result == null) return;

    setState(() {
      _ttsSource = result.source;
      _ttsConfig = result.config;
      _edgeVoices = result.edgeVoices;
    });
    await saveTtsProviderConfig(result.config);
    await saveEdgeVoices(result.edgeVoices);
    await saveTtsSource(result.source);
    if (!mounted) return;
    _toast.show(switch (result.source) {
      TtsSource.edge => '已切换为微软 Edge 发音',
      TtsSource.youdao => '已切换为有道词典发音',
      TtsSource.custom => '已启用自定义发音服务',
    });
  }

  Future<void> _openOcrSettings() async {
    final result = await showOcrSettingsModal(
      context,
      value: _customOcrConfig,
      credits: _quota.credits,
    );
    if (!mounted || result == null) return;

    switch (result) {
      case OcrSettingsSaveCustom(config: final cfg):
        setState(() => _customOcrConfig = cfg);
        await saveOcrProviderConfig(cfg);
        if (cfg != null) {
          _toast.show('已保存自定义 OCR 服务配置');
        } else if (requiresCustomOcrConfig()) {
          _toast.show('已清除 OCR 服务配置');
        } else {
          _toast.show('已恢复默认 OCR 服务配置');
        }
        await _quota.refresh();

      // 选内置模型时清掉自定义配置，好让内置服务（免费/高级）真正生效。
      case OcrSettingsSelectModel(modelId: final id):
        await saveSelectedModelId(id);
        setState(() => _customOcrConfig = null);
        await saveOcrProviderConfig(null);
        _toast.show('已切换到 ${getBuiltinModel(id).label}');
        await _quota.refresh();

      case OcrSettingsOpenRecharge():
        await _openRecharge();
    }
  }

  Future<void> _openRecharge() async {
    await showRechargeModal(
      context,
      credits: _quota.credits,
      onPurchase: (pack) async {
        await _quota.recharge(pack);
        _toast.show('已领取 +${pack.total} credits');
      },
    );
  }

  Future<void> _handleClearTtsCache() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '清空发音缓存',
      message: '确定要删除本地缓存的有道发音文件吗？\n下次听写会重新下载。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      final count = await clearTtsCache();
      _toast.show(count > 0 ? '已清空 $count 个发音缓存' : '暂无发音缓存');
    } catch (_) {
      _toast.show('清空发音缓存失败');
    }
  }

  /// 反馈：直接打开 GitHub Issues。
  ///
  /// 以前只是把地址塞进剪贴板，用户得自己切浏览器再粘贴。打不开
  /// （没有浏览器、Web 上被拦了弹窗）时仍然回落到复制，不至于什么都没发生。
  Future<void> _handleFeedback() async {
    final uri = Uri.parse('https://github.com/vvenv/alice/issues');
    try {
      final opened =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) return;
    } catch (_) {
      // 落到下面的复制兜底
    }
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (mounted) _toast.show('打不开浏览器，已复制反馈地址');
  }

  // --- 渲染 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quota = context.watch<OcrQuotaController>();
    final themeController = context.watch<ThemeController>();

    if (!_ready) {
      return Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(colors),
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: colors.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final usingCustom = isCustomOcrConfigSet(_customOcrConfig);
    final ocrDetail = usingCustom
        ? _customOcrConfig!.model
        : requiresCustomOcrConfig()
            ? '未配置'
            : quota.model.label;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(colors),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: ListView(
                        padding: const EdgeInsets.only(
                          left: Spacing.lg,
                          right: Spacing.lg,
                          top: Spacing.md,
                          bottom: Spacing.xxl,
                        ),
                        children: [
                          // 外观
                          _sectionLabel('外观', colors),
                          _card(colors, [
                            Padding(
                              padding: const EdgeInsets.all(Spacing.md),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _themeChip(
                                      colors,
                                      themeController,
                                      ThemeModeSetting.light,
                                      '浅色',
                                      AppIcons.sunny,
                                    ),
                                  ),
                                  const SizedBox(width: Spacing.sm),
                                  Expanded(
                                    child: _themeChip(
                                      colors,
                                      themeController,
                                      ThemeModeSetting.dark,
                                      '深色',
                                      AppIcons.moon,
                                    ),
                                  ),
                                  const SizedBox(width: Spacing.sm),
                                  Expanded(
                                    child: _themeChip(
                                      colors,
                                      themeController,
                                      ThemeModeSetting.system,
                                      '跟随系统',
                                      AppIcons.phonePortrait,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]),

                          // 声音
                          _sectionLabel('声音', colors),
                          _card(colors, [
                            _row(
                              colors,
                              icon: AppIcons.server,
                              label: '发音源',
                              detail: _ttsSourceDetail,
                              onTap: _openTtsSettings,
                            ),
                            _divider(colors),
                            _row(
                              colors,
                              icon: AppIcons.musicalNotes,
                              label: '提示音',
                              trailing: AppSwitch(
                                value: _soundOn,
                                onChanged: _handleToggleSound,
                              ),
                            ),
                            _divider(colors),
                            _row(
                              colors,
                              icon: AppIcons.vibration,
                              label: '触感反馈',
                              trailing: AppSwitch(
                                value: _hapticsOn,
                                onChanged: _handleToggleHaptics,
                              ),
                            ),
                            _divider(colors),
                            _row(
                              colors,
                              icon: AppIcons.language,
                              label: '朗读中文释义',
                              trailing: AppSwitch(
                                value: _readTranslationOn,
                                onChanged: _handleToggleReadTranslation,
                              ),
                            ),
                            _divider(colors),
                            _row(
                              colors,
                              icon: AppIcons.speedometer,
                              label: '语速',
                              detail: '${_speechRate.toStringAsFixed(1)}x',
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: Spacing.lg,
                                right: Spacing.lg,
                                bottom: Spacing.md,
                              ),
                              child: AppSlider(
                                min: kMinSpeechRate,
                                max: kMaxSpeechRate,
                                step: 0.1,
                                value: _speechRate,
                                onChanged: _handleSpeechRateChanged,
                                label: '朗读语速',
                                formatValue: (v) => '${v.toStringAsFixed(1)} 倍',
                              ),
                            ),
                          ]),

                          // 听写
                          _sectionLabel('听写', colors),
                          _card(colors, [
                            _row(
                              colors,
                              icon: AppIcons.timer,
                              label: '默认间隔',
                              detail: '${_intervalSec.toStringAsFixed(1)}s',
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: Spacing.lg,
                                right: Spacing.lg,
                                bottom: Spacing.md,
                              ),
                              child: AppSlider(
                                min: kMinIntervalSec,
                                max: kMaxIntervalSec,
                                step: kIntervalStep,
                                value: _intervalSec,
                                onChanged: _handleIntervalChanged,
                                label: '默认听写间隔秒数',
                                formatValue: (v) => '${v.toStringAsFixed(1)} 秒',
                              ),
                            ),
                          ]),

                          // 识别服务
                          _sectionLabel('识别服务', colors),
                          _card(colors, [
                            _row(
                              colors,
                              icon: AppIcons.scan,
                              label: '识别模型',
                              detail: ocrDetail,
                              onTap: _openOcrSettings,
                            ),
                            _divider(colors),
                            _row(
                              colors,
                              icon: AppIcons.wallet,
                              label: 'Credits 余额',
                              detail: '${quota.credits}',
                            ),
                            _divider(colors),
                            _row(
                              colors,
                              icon: AppIcons.card,
                              label: '领取演示积分',
                              onTap: _openRecharge,
                            ),
                          ]),
                          _disclaimer(colors),

                          // 数据
                          _sectionLabel('数据', colors),
                          _card(colors, [
                            _row(
                              colors,
                              icon: AppIcons.trash,
                              label: '清空发音缓存',
                              destructive: true,
                              onTap: _handleClearTtsCache,
                            ),
                          ]),

                          // 关于
                          _sectionLabel('关于', colors),
                          _card(colors, [
                            _row(
                              colors,
                              icon: AppIcons.infoOutline,
                              label: '版本',
                              detail: _appVersion,
                            ),
                            _divider(colors),
                            _row(
                              colors,
                              icon: AppIcons.chatbox,
                              label: '反馈',
                              detail: 'GitHub Issues',
                              onTap: _handleFeedback,
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AppToast(toast: _toast.toast, onActionPressed: _toast.hide),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.sm,
        bottom: Spacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppIconButton(
            icon: AppIcons.arrowBack,
            onPressed: () => Navigator.of(context).pop(),
            semanticLabel: '返回',
          ),
          Text(
            '设置',
            style: TextStyle(
              fontFamily: AppFonts.displayZh,
              fontSize: 18,
              letterSpacing: 0.3,
              color: colors.foreground,
            ),
          ),
          // 占位，让标题保持居中
          const SizedBox(width: 36, height: 36),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(
        top: Spacing.lg,
        bottom: Spacing.xs,
        left: Spacing.xs,
        right: Spacing.xs,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.subtle,
        ),
      ),
    );
  }

  Widget _card(AppColors colors, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _divider(AppColors colors) =>
      Divider(height: 0.5, thickness: 0.5, color: colors.borderSubtle);

  Widget _row(
    AppColors colors, {
    required IconData icon,
    required String label,
    String? detail,
    Widget? trailing,
    VoidCallback? onTap,
    bool destructive = false,
  }) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md + 2,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: destructive ? colors.danger : colors.secondary,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: destructive ? colors.danger : colors.foreground,
              ),
            ),
          ),
          if (detail != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.muted,
                ),
              ),
            ),
          if (trailing != null) ...[
            const SizedBox(width: Spacing.md),
            trailing,
          ],
          if (onTap != null) ...[
            const SizedBox(width: Spacing.md),
            Icon(AppIcons.chevronForward, size: 16, color: colors.subtle),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }

  Widget _themeChip(
    AppColors colors,
    ThemeController controller,
    ThemeModeSetting mode,
    String label,
    IconData icon,
  ) {
    final active = controller.mode == mode;

    return Semantics(
      selected: active,
      label: '$label主题',
      child: GestureDetector(
        onTap: () => controller.setMode(mode),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          decoration: BoxDecoration(
            color: active ? colors.primarySoft : colors.surface,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: active ? colors.primary : colors.border,
              width: 1.5,
            ),
          ),
          // 三档并排，「跟随系统」在窄屏 + 大号系统字体下会撑破自己那一格
          // —— 整体缩放而不是换行/裁字。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16, color: active ? colors.primary : colors.muted),
                const SizedBox(width: Spacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: active ? colors.primary : colors.foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _disclaimer(AppColors colors) {
    return Container(
      margin: const EdgeInsets.only(top: Spacing.sm),
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
          Icon(AppIcons.infoOutline, size: 13, color: colors.subtle),
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
}
