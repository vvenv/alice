import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_item.dart';
import '../models/word_history_entry.dart';
import '../services/credits.dart';
import '../services/dictation.dart';
import '../services/dictionary.dart';
import '../services/library_data.dart';
import '../services/ocr.dart';
import '../services/ocr_runner.dart';
import '../services/storage.dart';
import '../state/ocr_quota_controller.dart';
import '../state/toast_controller.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/favorites_drawer.dart';
import '../widgets/history_drawer.dart';
import '../widgets/library_drawer.dart';
import '../widgets/playback_controls.dart';
import '../widgets/recharge_modal.dart';
import '../widgets/word_input_section.dart';
import 'dictation_screen.dart';
import 'settings_screen.dart';

const String _sampleWords = 'apple\nbanana\ncat\ndog\nelephant\nfish\ngrape';
const Duration _wordInputSaveDebounce = Duration(milliseconds: 500);

List<T> _shuffleList<T>(List<T> items) {
  final shuffled = List<T>.from(items);
  final random = Random();
  for (var i = shuffled.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  return shuffled;
}

/// 首页。对应 RN 版 src/screens/HomeScreen.tsx。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _ready = false;
  String _wordInput = '';
  double _intervalSec = kDefaultIntervalSec;
  bool _autoNext = true;
  int _startIndex = 0;
  bool _shuffle = false;
  bool _isDisplayMode = false;
  OcrUiState _ocrUi = OcrUiState.idle;
  Alignment _cameraAlignment = kDefaultCameraButtonAlignment;

  List<WordHistoryEntry> _history = <WordHistoryEntry>[];
  List<String> _favorites = <String>[];
  late final List<LibraryGroup> _libraryGroups = getLibraryGroups();

  Timer? _debounce;
  late final ToastController _toast = ToastController();
  late final OcrRunner _ocr = OcrRunner(
    onResult: _handleOcrResult,
    // 识别是异步的，用户可能中途离开首页 —— 回调都要挡一道 mounted。
    onStateChange: (state) {
      if (mounted) setState(() => _ocrUi = state);
    },
    onOutcome: (message) {
      if (mounted) _toast.show(message);
    },
    onInsufficientCredits: () {
      if (mounted) _openRecharge();
    },
  );

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
    final results = await Future.wait([
      loadWordInput(),
      loadPersistedWrongWords(),
      loadWordHistory(),
      loadPersistedFavorites(),
      loadIntervalSec(),
      loadCameraButtonAlignment(),
    ]);
    if (!mounted) return;

    final savedInput = results[0] as String?;
    setState(() {
      if (savedInput != null && savedInput.isNotEmpty) {
        _wordInput = enrichWordListText(savedInput);
        _isDisplayMode = parseWords(_wordInput).isNotEmpty;
      }
      _history = results[2] as List<WordHistoryEntry>;
      _favorites = results[3] as List<String>;
      _intervalSec = results[4] as double;
      _cameraAlignment = results[5] as Alignment;
      _ready = true;
    });
  }

  @override
  void dispose() {
    // 退出时一律把最新输入落盘。只 cancel 防抖 timer 会把刚打的几秒钟丢掉，
    // 而「timer 还在不在」并不可靠 —— 干脆不依赖它。
    // 这里不 await：dispose 不能异步，SharedPreferences 的写入会自己走完。
    _debounce?.cancel();
    _debounce = null;
    unawaited(saveWordInput(_wordInput));
    _toast.removeListener(_onToastChanged);
    _toast.dispose();
    super.dispose();
  }

  // --- 拍照按钮落点 ---------------------------------------------------------

  void _handleCameraMoved(Alignment alignment) {
    setState(() => _cameraAlignment = alignment);
    // 一次拖动只写一次，不用防抖。
    unawaited(saveCameraButtonAlignment(alignment));
  }

  // --- 输入框持久化（防抖，避免每次按键都写存储）-------------------------

  void _onWordInputChanged(String value, {bool preferDisplay = false}) {
    setState(() {
      final wasEmpty = parseWords(_wordInput).isEmpty;
      _wordInput = value;
      final empty = parseWords(_wordInput).isEmpty;
      if (empty) {
        // 空列表只该停在编辑态；否则 _isDisplayMode 仍是 true，
        // 用户敲出第一个词就会立刻切到展示。
        _isDisplayMode = false;
      } else if (preferDisplay) {
        _isDisplayMode = true;
      } else if (wasEmpty) {
        _isDisplayMode = false;
      }
      _clampStartIndex();
    });
    if (!_ready) return;

    _debounce?.cancel();
    _debounce = Timer(_wordInputSaveDebounce, () async {
      await saveWordInput(_wordInput);
      // 展示模式下输入被视为已定稿 —— 立刻同步进历史，
      // 用户不必先开始听写。
      if (_isDisplayMode) {
        final enriched = enrichWordListText(_wordInput);
        if (parseWords(enriched).isNotEmpty) {
          await addWordHistory(enriched);
          final history = await loadWordHistory();
          if (mounted) setState(() => _history = history);
        }
      }
    });
  }

  /// 词数掉到 startIndex 以下时把游标收回来。
  void _clampStartIndex() {
    final count = parseWords(_wordInput).length;
    if (count == 0) {
      _startIndex = 0;
    } else if (_startIndex >= count) {
      _startIndex = count - 1;
    }
  }

  // --- 各类回调 -----------------------------------------------------------

  void _handleOcrResult(List<String> words) {
    if (!mounted) return;
    setState(() {
      // OCR 返回的是纯单词；立刻补全，好让展示模式有释义。
      _wordInput = enrichWordListText(words.join('\n'));
      _isDisplayMode = true;
      _clampStartIndex();
    });
    // 高级识别刚刚可能扣了 credits —— 同步余额。
    _quota.syncFromCache();
  }

  void _handleToggleDisplayMode() {
    setState(() {
      _isDisplayMode = !_isDisplayMode;
      // 退出编辑模式（「完成」）时补上离线词性 + 释义，并去掉重复词。
      if (_isDisplayMode) {
        _wordInput = enrichWordListText(_wordInput);
        _clampStartIndex();
      }
    });
  }

  void _handleIntervalChanged(double sec) {
    setState(() => _intervalSec = sec);
    saveIntervalSec(sec);
  }

  Future<void> _handleStart() async {
    // 即使用户从编辑模式直接开始，也保证补全过、去过重。
    final enriched = enrichWordListText(_wordInput);
    if (enriched != _wordInput) {
      setState(() {
        _wordInput = enriched;
        _clampStartIndex();
      });
    }

    final allWords = parseWords(enriched);
    if (allWords.isEmpty) {
      _toast.show('请先输入单词列表');
      return;
    }

    final clampedStart =
        _startIndex < allWords.length - 1 ? _startIndex : allWords.length - 1;
    var words = allWords.sublist(clampedStart);
    if (_shuffle) words = _shuffleList(words);

    await addWordHistory(enriched);
    final history = await loadWordHistory();
    if (!mounted) return;
    setState(() => _history = history);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DictationScreen(
          words: words,
          intervalSec: _intervalSec,
          autoNext: _autoNext,
        ),
      ),
    );

    // 听写页里可能调过间隔 —— 回来时重新读一次（对应 RN 的 useFocusEffect）。
    final sec = await loadIntervalSec();
    if (mounted) setState(() => _intervalSec = sec);
  }

  void _applyEntry(WordHistoryEntry entry, String toastMessage) {
    final text = entry.enrichedText ?? entry.text;
    setState(() {
      _wordInput = enrichWordListText(text);
      _isDisplayMode = true;
      _clampStartIndex();
    });
    _toast.show(toastMessage);
  }

  Future<void> _handleToggleFavorite(String id) async {
    await toggleFavorite(id);
    if (mounted) setState(() => _favorites = loadFavorites());
  }

  Future<void> _handleDeleteHistory(String id) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除记录',
      message: '确定要删除这条历史记录吗？',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() => _history = _history.where((e) => e.id != id).toList());
    // deleteWordHistory 也会顺手删掉对应的收藏。
    await deleteWordHistory(id);
    if (mounted) setState(() => _favorites = loadFavorites());
  }

  Future<void> _handleClearHistory() async {
    if (_history.isEmpty) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '清空历史',
      message: '确定要清空历史记录吗？',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed) return;

    await clearWordHistory();
    final history = await loadWordHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _favorites = loadFavorites();
      });
    }
  }

  Future<void> _openRecharge() async {
    await showRechargeModal(
      context,
      credits: _quota.credits,
      onPurchase: (pack) async {
        await _quota.recharge(pack);
        _toast.show('充值成功 +${pack.total} credits');
      },
    );
  }

  // --- 底部菜单 -----------------------------------------------------------

  Future<void> _openMenu() async {
    await showAppBottomSheet<void>(
      context: context,
      title: '更多',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetRow(
            icon: AppIcons.starOutline,
            label: '收藏',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openFavorites();
            },
          ),
          const SizedBox(height: Spacing.sm),
          SheetRow(
            icon: AppIcons.time,
            label: '历史记录',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openHistory();
            },
          ),
          const SizedBox(height: Spacing.sm),
          SheetRow(
            icon: AppIcons.library,
            label: '词库',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openLibrary();
            },
          ),
          const SizedBox(height: Spacing.sm),
          SheetRow(
            icon: AppIcons.settings,
            label: '设置',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openSettings();
            },
          ),
          const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    // 设置里可能改了默认间隔 / OCR 配置。
    if (!mounted) return;
    final sec = await loadIntervalSec();
    if (mounted) setState(() => _intervalSec = sec);
  }

  Future<void> _openFavorites() => showFavoritesDrawer(
        context,
        favorites: _favorites,
        history: _history,
        onApply: (entry) => _applyEntry(entry, '已载入收藏'),
        onToggleFavorite: _handleToggleFavorite,
      );

  Future<void> _openHistory() => showHistoryDrawer(
        context,
        history: _history,
        favorites: _favorites,
        onApply: (entry) => _applyEntry(entry, '已载入历史记录'),
        onDelete: _handleDeleteHistory,
        onClear: _handleClearHistory,
        onToggleFavorite: _handleToggleFavorite,
      );

  Future<void> _openLibrary() => showLibraryDrawer(
        context,
        groups: _libraryGroups,
        favorites: _favorites,
        onApply: (entry) => _applyEntry(entry, '已载入词库'),
        onToggleFavorite: _handleToggleFavorite,
      );

  Future<void> _openCameraSheet() async {
    final quota = context.read<OcrQuotaController>();

    await showAppBottomSheet<void>(
      context: context,
      title: '拍照识词',
      builder: (sheetContext) => ListenableBuilder(
        listenable: quota,
        builder: (context, _) {
          final colors = context.colors;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (quota.hasCustomConfig)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.surface),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(AppIcons.server, size: 16, color: colors.muted),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          '使用自定义服务',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.muted,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _openSettings();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          '设置',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    for (final m in kBuiltinModels) ...[
                      Expanded(
                        child: _ModelChip(
                          model: m,
                          active: quota.modelId == m.id,
                          onTap: () => quota.selectModel(m.id),
                        ),
                      ),
                      if (m != kBuiltinModels.last)
                        const SizedBox(width: Spacing.xs),
                    ],
                  ],
                ),
              const SizedBox(height: Spacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                child: Row(
                  children: [
                    Icon(AppIcons.wallet, size: 14, color: colors.subtle),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        'Credits: ${quota.credits}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: '充值',
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _openRecharge();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          '充值',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Container(
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
              ),
              const SizedBox(height: Spacing.sm),
              SheetRow(
                icon: AppIcons.cameraOutline,
                label: '拍摄照片',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _ocr.processPhoto();
                },
              ),
              const SizedBox(height: Spacing.sm),
              SheetRow(
                icon: AppIcons.images,
                label: '从相册选取',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _ocr.processAlbum();
                },
              ),
              const SizedBox(height: Spacing.sm),
            ],
          );
        },
      ),
    );
  }

  // --- 渲染 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (!_ready) {
      return Scaffold(
        backgroundColor: colors.surface,
        body: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    final parsedWordCount = parseWords(_wordInput).length;
    final canToggleDisplayMode = parsedWordCount > 0;
    final effectiveDisplayMode = _isDisplayMode && canToggleDisplayMode;
    final showOcrProgress = _ocrUi.busy && _ocrUi.message.isNotEmpty;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    // 拍照识词在打字时也留着 —— 「正在敲词表，想拍张照片导进来」恰恰是它最该
    // 出现的时候。只是键盘把列表压扁了，按钮跟着小一号，别盖住仅剩的输入区。
    final cameraSize = keyboardOpen ? 44.0 : 56.0;

    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 顶部金色光晕
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 180,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.goldSoft,
                        colors.goldSoft.withValues(alpha: 0)
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: !keyboardOpen,
            child: Column(
              children: [
                _buildHeader(showOcrProgress),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: Spacing.lg,
                          right: Spacing.lg,
                          bottom: Spacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSectionHeader(
                              parsedWordCount,
                              canToggleDisplayMode,
                              effectiveDisplayMode,
                            ),
                            Expanded(
                              child: WordInputSection(
                                value: _wordInput,
                                onChanged: _onWordInputChanged,
                                onSetSample: () => _onWordInputChanged(
                                  _sampleWords,
                                  preferDisplay: true,
                                ),
                                onClear: () => _onWordInputChanged(''),
                                startIndex: _startIndex,
                                onStartIndexChanged: (i) =>
                                    setState(() => _startIndex = i),
                                isDisplayMode: _isDisplayMode,
                                overlayActionSize: cameraSize,
                                overlayAlignment: _cameraAlignment,
                                onOverlayAlignmentChanged: _handleCameraMoved,
                                overlayAction: AppIconButton(
                                  icon: AppIcons.camera,
                                  size: cameraSize,
                                  variant: IconButtonVariant.gold,
                                  onPressed: _openCameraSheet,
                                  semanticLabel: '拍照识词',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!keyboardOpen) _buildBottomPanel(parsedWordCount),
              ],
            ),
          ),
          AppToast(toast: _toast.toast, onActionPressed: _toast.hide),
        ],
      ),
    );
  }

  Widget _buildHeader(bool showOcrProgress) {
    final colors = context.colors;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.md,
            bottom: Spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(AppIcons.time, size: 26, color: colors.gold),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      'Alice',
                      style: TextStyle(
                        fontFamily: AppFonts.displayItalic,
                        fontSize: 24,
                        letterSpacing: 0.3,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      '听写',
                      style: TextStyle(
                        fontFamily: AppFonts.displayZh,
                        fontSize: 24,
                        letterSpacing: 0.3,
                        color: colors.rose,
                      ),
                    ),
                  ],
                ),
              ),
              if (showOcrProgress)
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primarySoft,
                      borderRadius: BorderRadius.circular(Radii.full),
                      border: Border.all(color: colors.primary),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        Flexible(
                          child: Text(
                            _ocrUi.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: Spacing.sm),
              AppIconButton(
                icon: AppIcons.menu,
                onPressed: _openMenu,
                semanticLabel: '菜单',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题行不再写「单词列表」——输入框 placeholder 已经说明用途。
  /// 空着不占文案；编辑中报词数；展示态改成「从 xx 开始」，把点选起点说清楚。
  String? _sectionTitle(int parsedWordCount, bool effectiveDisplayMode) {
    if (parsedWordCount == 0) return null;
    if (!effectiveDisplayMode) return '$parsedWordCount 个单词';
    final words = parseWords(_wordInput);
    if (_startIndex < 0 || _startIndex >= words.length) {
      return '$parsedWordCount 个单词';
    }
    return '从 ${parseWordLine(words[_startIndex]).word} 开始';
  }

  Widget _buildSectionHeader(
    int parsedWordCount,
    bool canToggleDisplayMode,
    bool effectiveDisplayMode,
  ) {
    final colors = context.colors;
    final title = _sectionTitle(parsedWordCount, effectiveDisplayMode);
    final showCountBadge = effectiveDisplayMode && parsedWordCount > 0;

    return Padding(
      key: const Key('word-list-header'),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.displayZh,
                            fontSize: 17,
                            letterSpacing: 0.3,
                            color: colors.foreground,
                          ),
                        ),
                      ),
                      if (showCountBadge) ...[
                        const SizedBox(width: Spacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(Radii.full),
                            border: Border.all(color: colors.border),
                          ),
                          child: Text(
                            '$parsedWordCount 词',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.muted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          // 空列表没有切换按钮，但仍占住 sm 按钮的高度，避免标题行跟着跳。
          Visibility(
            visible: canToggleDisplayMode,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: AppButton(
              label: effectiveDisplayMode ? '编辑' : '完成',
              icon: effectiveDisplayMode
                  ? AppIcons.createOutline
                  : AppIcons.checkmark,
              size: ButtonSize.sm,
              active: !effectiveDisplayMode,
              onPressed: _handleToggleDisplayMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(int parsedWordCount) {
    final colors = context.colors;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          padding: const EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.md,
            bottom: Spacing.md,
          ),
          child: PlaybackControls(
            intervalSec: _intervalSec,
            autoNext: _autoNext,
            onIntervalChanged: _handleIntervalChanged,
            onAutoNextChanged: (v) => setState(() => _autoNext = v),
            onPlayToggle: _handleStart,
            shuffle: _shuffle,
            onShuffleChanged: (v) => setState(() => _shuffle = v),
            wordCount: parsedWordCount,
          ),
        ),
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.model,
    required this.active,
    required this.onTap,
  });

  final BuiltinModel model;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      selected: active,
      label: model.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.md,
          ),
          decoration: BoxDecoration(
            color: active ? colors.primarySoft : colors.surface,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: active ? colors.primary : colors.borderSubtle,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                model.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? colors.primary : colors.foreground,
                ),
              ),
              if (model.tier == ModelTier.premium) ...[
                const SizedBox(height: 2),
                Text(
                  '${model.creditCost} credit',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? colors.gold : colors.subtle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
