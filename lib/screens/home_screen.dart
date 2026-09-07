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
import '../services/ocr_config.dart';
import '../services/ocr_runner.dart';
import '../services/share_intake.dart';
import '../services/storage.dart';
import '../services/tts.dart';
import '../state/ocr_quota_controller.dart';
import '../state/toast_controller.dart';
import '../theme/app_colors.dart';
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
import '../widgets/ocr_settings_modal.dart';
import '../widgets/playback_controls.dart';
import '../widgets/recharge_modal.dart';
import '../widgets/word_input_section.dart';
import '../widgets/wrong_words_drawer.dart';
import 'dictation_screen.dart';
import 'settings_screen.dart';

const Duration _wordInputSaveDebounce = Duration(milliseconds: 500);

/// 首启示例词表。
///
/// 空输入框 + 一句 hint 对新用户不够：点「开始听写」只会换来一句
/// 「请先输入单词列表」，谁也没看见这个应用到底怎么运作。给一条一秒钟就能
/// 走通全流程的路。词性与释义由 enrichWordListText 从内置词典补。
const List<String> _sampleWords = [
  'rabbit',
  'garden',
  'mirror',
  'whisper',
  'holiday',
  'castle',
  'brave',
  'curious',
];

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
    onNeedsOcrConfig: () {
      if (mounted) _openOcrSettings();
    },
  );

  OcrQuotaController get _quota => context.read<OcrQuotaController>();

  @override
  void initState() {
    super.initState();
    _toast.addListener(_onToastChanged);
    ShareIntake.listen(_applySharedText);
    _bootstrap();
  }

  void _onToastChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([
      loadWordInput(),
      // 结果用不上，但这一次是必需的：它把累计错词本读进内存缓存，
      // 之后同步的 loadWrongWords() 才有东西可读（错词本抽屉靠它）。
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
    unawaited(_enrichWhenDictionaryReady());
    unawaited(_consumePendingShare());
  }

  /// 冷启动是被分享拉起来的：原生侧先把文本存着，这里取一次。
  Future<void> _consumePendingShare() async {
    final text = await ShareIntake.takePending();
    if (text == null || !mounted) return;
    _applySharedText(text);
  }

  /// 把分享进来的文本当词表用。
  ///
  /// 直接覆盖当前列表 —— 用户刚从别处分享过来，要的就是这一份。原来那份
  /// 已经在历史里（展示模式下输入就会同步进历史），撤销也留一手。
  void _applySharedText(String text) {
    final normalized = normalizeSharedText(text);
    final words = parseWords(normalized);
    if (words.isEmpty || !mounted) return;

    final previous = _wordInput;
    setState(() {
      _wordInput = enrichWordListText(normalized);
      _isDisplayMode = true;
      _startIndex = 0;
    });
    _debounce?.cancel();
    unawaited(saveWordInput(_wordInput));

    _toast.show(
      '已载入分享的 ${words.length} 个词',
      action: previous.trim().isEmpty
          ? null
          : ToastAction(
              label: '撤销',
              onPressed: () {
                setState(() {
                  _wordInput = previous;
                  _isDisplayMode = parseWords(previous).isNotEmpty;
                  _clampStartIndex();
                });
                unawaited(saveWordInput(previous));
              },
            ),
    );
  }

  Future<void> _enrichWhenDictionaryReady() async {
    await loadDictionary();
    if (!mounted || _wordInput.isEmpty) return;
    final enriched = enrichWordListText(_wordInput);
    if (enriched != _wordInput) {
      setState(() => _wordInput = enriched);
    }
  }

  @override
  void dispose() {
    // 退出时一律把最新输入落盘。只 cancel 防抖 timer 会把刚打的几秒钟丢掉，
    // 而「timer 还在不在」并不可靠 —— 干脆不依赖它。
    // 这里不 await：dispose 不能异步，SharedPreferences 的写入会自己走完。
    _debounce?.cancel();
    _debounce = null;
    unawaited(saveWordInput(_wordInput));
    ShareIntake.stopListening();
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

  void _onWordInputChanged(String value) {
    setState(() {
      final wasEmpty = parseWords(_wordInput).isEmpty;
      _wordInput = value;
      final empty = parseWords(_wordInput).isEmpty;
      if (empty || wasEmpty) {
        // 空列表只该停在编辑态；否则 _isDisplayMode 仍是 true，
        // 用户敲出第一个词就会立刻切到展示。
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
    await loadDictionary();
    if (!mounted) return;
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

    await _launchDictation(words, historyText: enriched);
  }

  /// 从错词本直接开一轮听写。
  ///
  /// 顺手把首页的列表也换成这些词：听完返回时看到的就是刚练的那一份，
  /// 而不是听写前那份不相干的列表。
  Future<void> _handleStartWrongWords(List<String> wrongWords) async {
    if (wrongWords.isEmpty) return;

    await loadDictionary();
    if (!mounted) return;

    final enriched = enrichWordListText(wrongWords.join('\n'));
    final words = parseWords(enriched);
    if (words.isEmpty) return;

    setState(() {
      _wordInput = enriched;
      _isDisplayMode = true;
      _startIndex = 0;
    });
    _debounce?.cancel();
    unawaited(saveWordInput(enriched));

    await _launchDictation(
      _shuffle ? _shuffleList(words) : words,
      historyText: enriched,
    );
  }

  /// 开始听写的公共尾段：预热音频、记历史、进页、回来后同步间隔。
  Future<void> _launchDictation(
    List<String> words, {
    required String historyText,
  }) async {
    // 趁着点击手势还在：激活音频会话，并给前两个词开始预取。
    // 进页后再开口会丢手势，第一句经常被 iOS 吃掉；下载也不挡播放，
    // 只是转场这几百毫秒里能多抢到一点缓存。
    unawaited(preparePlayback());
    unawaited(prefetchWordAudio(speakTextFromEntry(words[0])));
    if (words.length > 1) {
      unawaited(prefetchWordAudio(speakTextFromEntry(words[1])));
    }

    await addWordHistory(historyText);
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

  /// 删掉一行之后给一次撤销。
  ///
  /// 那个删除按钮是列表行里一个 20px 的 ✕，误触代价不小 —— 刚 OCR 识出来
  /// 三十个词，误删一个就得重拍。错词删除一直有撤销，这里没有说不过去。
  void _handleWordDeleted(int index, String line) {
    final word = parseWordLine(line).word;
    _toast.show(
      '已删除 $word',
      action: ToastAction(
        label: '撤销',
        onPressed: () {
          final entries = parseWords(_wordInput);
          entries.insert(index.clamp(0, entries.length), line);
          final restored = entries.join('\n');
          setState(() {
            _wordInput = restored;
            _isDisplayMode = true;
            _clampStartIndex();
          });
          _debounce?.cancel();
          unawaited(saveWordInput(restored));
        },
      ),
    );
  }

  /// 清空词表 —— 换一份词表以前要全选删。同样给一次撤销。
  void _handleClearWordInput() {
    final previous = _wordInput;
    if (parseWords(previous).isEmpty) return;

    setState(() {
      _wordInput = '';
      _isDisplayMode = false;
      _startIndex = 0;
    });
    _debounce?.cancel();
    unawaited(saveWordInput(''));

    _toast.show(
      '已清空词表',
      action: ToastAction(
        label: '撤销',
        onPressed: () {
          setState(() {
            _wordInput = previous;
            _isDisplayMode = true;
            _clampStartIndex();
          });
          unawaited(saveWordInput(previous));
        },
      ),
    );
  }

  /// 一键填入示例词表，让首启的用户能直接走通一轮听写。
  Future<void> _handleLoadSample() async {
    await loadDictionary();
    if (!mounted) return;

    final enriched = enrichWordListText(_sampleWords.join('\n'));
    setState(() {
      _wordInput = enriched;
      _isDisplayMode = true;
      _startIndex = 0;
    });
    _debounce?.cancel();
    unawaited(saveWordInput(enriched));
    _toast.show('已载入 ${_sampleWords.length} 个示例单词');
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
        _toast.show('已领取 +${pack.total} credits');
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
            icon: AppIcons.wrongWords,
            label: '错词本',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openWrongWords();
            },
          ),
          const SizedBox(height: Spacing.sm),
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

  Future<void> _openOcrSettings() async {
    final custom = await loadOcrProviderConfig();
    if (!mounted) return;
    final result = await showOcrSettingsModal(
      context,
      value: custom,
      credits: _quota.credits,
    );
    if (!mounted || result == null) return;

    switch (result) {
      case OcrSettingsSaveCustom(config: final cfg):
        await saveOcrProviderConfig(cfg);
        if (cfg != null) {
          _toast.show('已保存自定义 OCR 服务配置');
        } else if (requiresCustomOcrConfig()) {
          _toast.show('已清除 OCR 服务配置');
        } else {
          _toast.show('已恢复默认 OCR 服务配置');
        }
        await _quota.refresh();

      case OcrSettingsSelectModel(modelId: final id):
        await saveSelectedModelId(id);
        await saveOcrProviderConfig(null);
        _toast.show('已切换到 ${getBuiltinModel(id).label}');
        await _quota.refresh();

      case OcrSettingsOpenRecharge():
        await _openRecharge();
    }
  }

  Future<void> _openWrongWords() => showWrongWordsDrawer(
        context,
        onStartDictation: (words) => unawaited(_handleStartWrongWords(words)),
        onMessage: _toast.show,
      );

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
          final needsKey = requiresCustomOcrConfig() && !quota.hasCustomConfig;

          if (needsKey) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  child: Text(
                    'Web 版没有内置识别服务。请先在设置中填入自己的 OCR API Key，'
                    '粘贴词表和内置词库不需要这一步。',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: colors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                SheetRow(
                  icon: AppIcons.scan,
                  label: '去配置 OCR 服务',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openOcrSettings();
                  },
                ),
                const SizedBox(height: Spacing.sm),
              ],
            );
          }

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
                          _openOcrSettings();
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
                      label: '领取演示积分',
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _openRecharge();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          '领取',
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
    final quota = context.watch<OcrQuotaController>();

    if (!_ready) {
      return Scaffold(
        backgroundColor: colors.surface,
        body: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    final parsedWordCount = parseWords(_wordInput).length;
    final showOcrProgress = _ocrUi.busy && _ocrUi.message.isNotEmpty;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final showOcrSetupBanner =
        requiresCustomOcrConfig() && !quota.hasCustomConfig;
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
                if (showOcrSetupBanner) _buildOcrSetupBanner(),
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
                            Expanded(
                              child: WordInputSection(
                                value: _wordInput,
                                onChanged: _onWordInputChanged,
                                startIndex: _startIndex,
                                onStartIndexChanged: (i) =>
                                    setState(() => _startIndex = i),
                                isDisplayMode: _isDisplayMode,
                                onToggleDisplayMode: _handleToggleDisplayMode,
                                onWordDeleted: _handleWordDeleted,
                                onClearAll: _handleClearWordInput,
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

  Widget _buildOcrSetupBanner() {
    final colors = context.colors;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.sm,
          ),
          child: Semantics(
            button: true,
            label: '配置 OCR 服务',
            child: GestureDetector(
              onTap: _openOcrSettings,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(Radii.surface),
                  border: Border.all(color: colors.primary),
                ),
                child: Row(
                  children: [
                    Icon(AppIcons.scan, size: 16, color: colors.primary),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        'Web 版拍照识词需自备 API Key，点此配置。词库与粘贴不需要。',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    Icon(
                      AppIcons.chevronForward,
                      size: 16,
                      color: colors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
              // 320px 宽的机型上这块标题正好差一点点放不下（放大系统字号后
              // 差得更多），会被裁掉半个「写」字。整体等比缩，别拆开换行 ——
              // 怀表 + Alice 听写 是一个整体的品牌锁定。
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                icon: AppIcons.library,
                onPressed: _openLibrary,
                semanticLabel: '词库',
              ),
              const SizedBox(width: Spacing.xs),
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

  /// 一个词都没有时的两条出路。
  ///
  /// 空输入框此前只有输入框里那句 hint；新用户点「开始听写」，得到的是
  /// 「请先输入单词列表」—— 一次没有出口的挫败。
  Widget _buildEmptyStateRow(AppColors colors) {
    // Wrap 而不是 Row：说明 + 两颗按钮在 320px 宽的机型上正好差一点点
    // （放大系统字号后差得更多），挤不下就换行，别去裁按钮。
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.sparkles, size: 15, color: colors.gold),
            const SizedBox(width: Spacing.xs),
            Text(
              '第一次用？',
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
          ],
        ),
        AppButton(
          label: '载入示例',
          size: ButtonSize.sm,
          variant: ButtonVariant.ghost,
          onPressed: () => unawaited(_handleLoadSample()),
        ),
        AppButton(
          label: '浏览词库',
          size: ButtonSize.sm,
          variant: ButtonVariant.ghost,
          onPressed: () => unawaited(_openLibrary()),
        ),
      ],
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (parsedWordCount == 0) ...[
                _buildEmptyStateRow(colors),
                const SizedBox(height: Spacing.md),
              ],
              PlaybackControls(
                intervalSec: _intervalSec,
                autoNext: _autoNext,
                onIntervalChanged: _handleIntervalChanged,
                onAutoNextChanged: (v) => setState(() => _autoNext = v),
                onPlayToggle: _handleStart,
                shuffle: _shuffle,
                onShuffleChanged: (v) => setState(() => _shuffle = v),
                wordCount: parsedWordCount,
              ),
            ],
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
