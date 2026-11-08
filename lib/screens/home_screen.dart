import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/custom_word_list.dart';
import '../models/library_item.dart';
import '../models/word_history_entry.dart';
import '../services/app_update.dart';
import '../services/ocr_models.dart';
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
import '../widgets/update_dialog.dart';
import '../widgets/word_input_section.dart';
import '../widgets/wrong_words_drawer.dart';
import 'dictation_screen.dart';
import 'image_edit_screen.dart';
import 'settings_screen.dart';

const Duration _wordInputSaveDebounce = Duration(milliseconds: 500);

List<T> _shuffleList<T>(List<T> items, [Random? random]) {
  final shuffled = List<T>.from(items);
  final rng = random ?? Random();
  for (var i = shuffled.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  return shuffled;
}

/// 测试里把乱序钉成固定种子。正式包永远是 null，走真随机。
@visibleForTesting
Random? debugShuffleRandom;

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
  int _savedStartIndex = 0;
  bool _shuffle = false;
  bool _isDisplayMode = false;

  /// 看的是上一次播出的词序，而不是正在编辑的草稿。
  bool _showingLast = false;
  String _lastPlayback = '';
  int _lastStartIndex = 0;
  List<CustomWordList> _customLists = <CustomWordList>[];
  OcrUiState _ocrUi = OcrUiState.idle;
  bool _starting = false;
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
    onNeedsOcrConfig: () {
      if (mounted) _openOcrSettings();
    },
    editImage: _editOcrImage,
  );

  Future<XFile?> _editOcrImage(XFile file) async {
    if (!mounted) return null;
    return openImageEditor(context, file);
  }

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

  /// 起点一变就落盘。
  ///
  /// 改 [_startIndex] 的地方有十来处（点词、删词、清空、载入、撤销、听写进度），
  /// 逐处补一句保存迟早漏掉一处，所以挂在 setState 上统一收口。
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!_ready || _startIndex == _savedStartIndex) return;
    _savedStartIndex = _startIndex;
    unawaited(saveStartIndex(_startIndex));
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
      loadStartIndex(),
      loadLastPlayback(),
      loadCustomLists(),
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
      // 上次听到哪就停在哪 —— 词表本来就会恢复，起点不跟着恢复的话，
      // 听到第 30 个词退出去，回来又得自己翻回去找。
      _startIndex = _savedStartIndex = results[6] as int;
      _lastPlayback = results[7] as String;
      _customLists = results[8] as List<CustomWordList>;
      _clampStartIndex();
      _ready = true;
    });
    unawaited(_enrichWhenDictionaryReady());
    unawaited(_consumePendingShare());
    unawaited(_checkForUpdate());
  }

  /// 启动时看一眼官网有没有新版 APK。
  ///
  /// 只在 release 包里做：debug 包的 versionCode 和线上一样或更高，查了也白查，
  /// 而且 widget 测试不该碰网络。
  Future<void> _checkForUpdate() async {
    if (!kReleaseMode) return;
    final info = await checkUpdateOnLaunch();
    // 用户这时可能已经进了听写 / 设置页，别把框盖在别的页面上 —— 下次启动再说。
    if (info == null || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final ok = await showAppUpdateDialog(context, info);
    if (!ok && mounted) _toast.show('更新失败，已复制下载地址');
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
      _showingLast = false;
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
      _showingLast = false;
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
    final count = parseWords(_activeListText).length;
    if (count == 0) {
      _activeStartIndex = 0;
    } else if (_activeStartIndex >= count) {
      _activeStartIndex = count - 1;
    }
  }

  /// 卡片上正在看的那份：草稿，或上一次播出的词序。
  String get _activeListText => _showingLast ? _lastPlayback : _wordInput;

  int get _activeStartIndex => _showingLast ? _lastStartIndex : _startIndex;

  set _activeStartIndex(int value) {
    if (_showingLast) {
      _lastStartIndex = value;
    } else {
      _startIndex = value;
    }
  }

  /// 上次听写和当前草稿不是同一份时才值得切过去。
  bool get _canShowLast {
    final last = parseWords(_lastPlayback);
    if (last.isEmpty) return false;
    return plainWordList(_lastPlayback) != plainWordList(_wordInput);
  }

  void _showCurrentList() {
    if (!_showingLast) return;
    setState(() => _showingLast = false);
  }

  // --- 各类回调 -----------------------------------------------------------

  void _handleOcrResult(List<String> words) {
    if (!mounted) return;
    setState(() {
      _showingLast = false;
      // OCR 返回的是纯单词；立刻补全，好让展示模式有释义。
      _wordInput = enrichWordListText(words.join('\n'));
      _isDisplayMode = true;
      _startIndex = 0;
    });
    _debounce?.cancel();
    unawaited(saveWordInput(_wordInput));
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
    if (_starting) return;

    // 即使用户从编辑模式直接开始，也保证补全过、去过重。
    //
    // 词典是 3.4MB 的资源，Web 上第一次要现拉。以前这里干等着，用户点了
    // 「开始听写」什么也不会发生 —— 现在按钮进入准备态，并挡住重复点击。
    if (!isDictionaryLoaded) setState(() => _starting = true);
    try {
      await loadDictionary();
    } finally {
      if (mounted && _starting) setState(() => _starting = false);
    }
    if (!mounted) return;
    final enriched = enrichWordListText(_wordInput);
    if (!_showingLast && enriched != _wordInput) {
      setState(() {
        _wordInput = enriched;
        _clampStartIndex();
      });
    }

    // 看的是上次听写时按那份播出，不拿草稿去补全、也不改草稿。
    final source = _showingLast ? _lastPlayback : enriched;
    final allWords = parseWords(source);
    if (allWords.isEmpty) {
      _toast.show('请先输入单词列表');
      return;
    }

    final activeStart = _activeStartIndex;
    final clampedStart =
        activeStart < allWords.length - 1 ? activeStart : allWords.length - 1;
    var words = allWords.sublist(clampedStart);
    final shuffled = _shuffle && !_showingLast;
    if (shuffled) {
      words = [
        for (final entry in _shuffleList(
          parseWordEntries(words.join('\n')),
          debugShuffleRandom,
        ))
          entryToLine(entry),
      ];
    }

    // 从编辑态直接开始时防抖还没到点 —— 先落盘，杀掉应用也丢不了这份词表。
    if (!_showingLast) {
      _debounce?.cancel();
      unawaited(saveWordInput(enriched));
    }

    // 从当前词表开的这一轮，播出顺序和草稿不一样（乱序，或从中间听）就记下。
    // 正在复习「上次听写」时不改写：从中间再听只是复习，完整顺序还要留着对答案。
    // 正序整表和草稿相同，就不单独留一份。
    final played = words.join('\n');
    if (!_showingLast &&
        parseWords(played).isNotEmpty &&
        plainWordList(played) != plainWordList(_wordInput)) {
      unawaited(saveLastPlayback(played));
      if (mounted) {
        setState(() {
          _lastPlayback = played;
          _lastStartIndex = 0;
        });
      }
    } else if (!_showingLast &&
        plainWordList(played) == plainWordList(_wordInput)) {
      // 没打乱，或打乱结果碰巧和原文一样：上次听写没有单独存在的必要。
      if (_lastPlayback.isNotEmpty) {
        unawaited(saveLastPlayback(''));
        if (mounted) {
          setState(() {
            _lastPlayback = '';
            _showingLast = false;
            _lastStartIndex = 0;
          });
        }
      }
    }

    await _launchDictation(
      words,
      historyText: shuffled ? played : (_showingLast ? _wordInput : enriched),
      // 乱序之后听写页的下标和当前词表行号对不上。
      // 看的是上次听写时，进度记在上次那一份上。
      anchorBase: shuffled ? null : clampedStart,
      trackLast: _showingLast,
    );
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

    final shuffled = _shuffle;
    final played = shuffled
        ? [
            for (final entry in _shuffleList(
              parseWordEntries(words.join('\n')),
              debugShuffleRandom,
            ))
              entryToLine(entry),
          ]
        : words;
    final playedText = played.join('\n');
    if (shuffled && plainWordList(playedText) != plainWordList(enriched)) {
      unawaited(saveLastPlayback(playedText));
      if (mounted) {
        setState(() {
          _lastPlayback = playedText;
          _lastStartIndex = 0;
          _showingLast = false;
        });
      }
    }

    await _launchDictation(
      played,
      historyText: shuffled ? playedText : enriched,
      anchorBase: shuffled ? null : 0,
    );
  }

  /// 开始听写的公共尾段：预热音频、记历史、进页、回来后同步间隔。
  ///
  /// [anchorBase] 是 [words] 第一个词在首页词表里的行号；给了它，听写每换
  /// 一个词首页的起点就跟一步，听完整份再回到开头。为 null 则不跟。
  Future<void> _launchDictation(
    List<String> words, {
    required String historyText,
    int? anchorBase,
    bool trackLast = false,
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
          onIndexChanged: anchorBase == null
              ? null
              : (i) => trackLast
                  ? _moveLastStartIndex(anchorBase + i)
                  : _moveStartIndex(anchorBase + i, from: historyText),
          onCompleted: anchorBase == null
              ? null
              : () => trackLast
                  ? _moveLastStartIndex(0)
                  : _moveStartIndex(0, from: historyText),
        ),
      ),
    );

    // 听写页里可能调过间隔 —— 回来时重新读一次（对应 RN 的 useFocusEffect）。
    final sec = await loadIntervalSec();
    if (!mounted) return;
    setState(() {
      _intervalSec = sec;
      // 从当前词表乱序听完，回来停在播出顺序上对答案，起点回到开头。
      // 本来就在看上次听写时，起点由听写页回调维护；这里再写成 0
      // 会把中途退出的位置盖掉。
      if (!trackLast &&
          _canShowLast &&
          plainWordList(words.join('\n')) == plainWordList(_lastPlayback)) {
        _showingLast = true;
        _lastStartIndex = 0;
      }
    });
  }

  /// 听写页报来的进度。首页此刻压在听写页底下，照样更新 —— 落盘靠的就是它。
  void _moveStartIndex(int index, {required String from}) {
    // 词表在听写期间被换掉了（分享进来一份新的）：行号已经不是一回事。
    if (!mounted || from != _wordInput) return;
    setState(() {
      _startIndex = index;
      _clampStartIndex();
    });
  }

  void _moveLastStartIndex(int index) {
    if (!mounted || !_showingLast) return;
    setState(() {
      _lastStartIndex = index;
      _clampStartIndex();
    });
  }

  /// 删掉一行之后给一次撤销。
  ///
  /// 左滑一下或点行尾的 ✕ 就删了，误触代价不小 —— 刚 OCR 识出来
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
    if (_showingLast) {
      final previous = _lastPlayback;
      setState(() {
        _lastPlayback = '';
        _showingLast = false;
        _lastStartIndex = 0;
      });
      unawaited(saveLastPlayback(''));
      _toast.show(
        '已清除上次听写',
        action: ToastAction(
          label: '撤销',
          onPressed: () {
            setState(() {
              _lastPlayback = previous;
              _showingLast = _canShowLast;
              _lastStartIndex = 0;
            });
            unawaited(saveLastPlayback(previous));
          },
        ),
      );
      return;
    }

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

  void _applyEntry(WordHistoryEntry entry, String toastMessage) {
    final text = entry.enrichedText ?? entry.text;
    setState(() {
      _showingLast = false;
      _wordInput = enrichWordListText(text);
      _isDisplayMode = true;
      // 换了一份词表，旧起点没有意义。
      _startIndex = 0;
    });
    // 载入即落盘：以前只有打字才会存，从词库载入一份、听到一半杀掉应用，
    // 回来看到的是更早那份。
    _debounce?.cancel();
    unawaited(saveWordInput(_wordInput));
    _toast.show(toastMessage);
  }

  Future<void> _saveActiveListToLibrary({bool toast = true}) async {
    final text = _activeListText;
    if (parseWords(text).isEmpty) {
      if (toast) _toast.show('词表是空的');
      return;
    }
    if (!mounted) return;
    final name = await showTextPromptDialog(
      context,
      title: '存入词库',
      message: '给这份词表起个名字，下次从「我的词库」里直接载入。',
      initialValue: suggestCustomListName(text),
      hintText: '词表名称',
    );
    if (name == null || !mounted) return;

    final saved = await saveCustomList(name: name, text: text);
    if (!mounted) return;
    if (saved == null) {
      _toast.show('没存上，再试一次');
      return;
    }
    final lists = await loadCustomLists();
    if (!mounted) return;
    setState(() => _customLists = lists);
    if (toast) _toast.show('已存入「${saved.name}」');
  }

  Future<void> _handleDeleteCustom(String id) async {
    final list = _customLists.where((e) => e.id == id);
    final name = list.isEmpty ? '这份词表' : list.first.name;
    final confirmed = await showConfirmDialog(
      context,
      title: '删除词表',
      message: '确定要删除「$name」吗？',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _customLists = _customLists.where((e) => e.id != id).toList());
    await deleteCustomList(id);
    if (mounted) setState(() => _favorites = loadFavorites());
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

  // --- 底部菜单 -----------------------------------------------------------
  //
  // 只在窄屏出现，装的是页头放不下的那几项（见 _buildHeader）。词库和收藏
  // 已经在页头上了，这里不再重复。

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
        customLists: _customLists,
        onApply: (entry) {
          _showCurrentList();
          _applyEntry(entry, '已载入收藏');
        },
        onToggleFavorite: _handleToggleFavorite,
      );

  Future<void> _openHistory() => showHistoryDrawer(
        context,
        history: _history,
        favorites: _favorites,
        onApply: (entry) {
          _showCurrentList();
          _applyEntry(entry, '已载入历史记录');
        },
        onDelete: _handleDeleteHistory,
        onClear: _handleClearHistory,
        onToggleFavorite: _handleToggleFavorite,
      );

  Future<void> _openLibrary() => showLibraryDrawer(
        context,
        groups: _libraryGroups,
        favorites: _favorites,
        customLists: _customLists,
        onSaveCurrent: parseWords(_activeListText).isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_saveActiveListToLibrary());
              },
        onDeleteCustom: (id) => unawaited(_handleDeleteCustom(id)),
        onApply: (entry) {
          _showCurrentList();
          _applyEntry(entry, '已载入词库');
        },
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
                        // 纯文字只有十几像素高；撑到 44 再点。
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.sm,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '设置',
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
                  // 先启动选图，再关抽屉。Web 的文件选择必须落在这次
                  // 点击的同步调用栈里；原生上也能避开「关抽屉的同时
                  // present 相机 / 相册」失败。
                  _ocr.processPhoto();
                  Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: Spacing.sm),
              SheetRow(
                icon: AppIcons.images,
                label: '从相册选取',
                onTap: () {
                  _ocr.processAlbum();
                  Navigator.of(sheetContext).pop();
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

    final activeText = _activeListText;
    final parsedWordCount = parseWords(activeText).length;
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
                // toast 放在这一层而不是整页最外层：它原先固定贴屏幕底，正好
                // 压在「开始听写」上 —— 载入词表和开始听写是连着的两步，主按钮
                // 恰好在这几秒里被盖住。挂在内容区里，它就浮在底部面板之上。
                Expanded(
                  // fit: expand —— 外层 Column 给的是宽度松约束，Stack 默认按
                  // 非定位子项定宽，而 toast 为空时是 0×0，整块会塌成 0 宽，
                  // 画面照旧但点击全部落空。
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
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
                                if (_canShowLast)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: Spacing.sm,
                                    ),
                                    child: _ListSourceSwitch(
                                      showingLast: _showingLast,
                                      onChanged: (last) => setState(() {
                                        _showingLast = last;
                                        _clampStartIndex();
                                      }),
                                    ),
                                  ),
                                Expanded(
                                  child: WordInputSection(
                                    value: activeText,
                                    onChanged: _showingLast
                                        ? (_) {}
                                        : _onWordInputChanged,
                                    startIndex: _activeStartIndex,
                                    onStartIndexChanged: (i) => setState(() {
                                      _activeStartIndex = i;
                                    }),
                                    isDisplayMode:
                                        _showingLast || _isDisplayMode,
                                    onToggleDisplayMode: _showingLast
                                        ? null
                                        : _handleToggleDisplayMode,
                                    onWordDeleted: _showingLast
                                        ? null
                                        : _handleWordDeleted,
                                    onClearAll: _handleClearWordInput,
                                    onSave: parseWords(activeText).isEmpty
                                        ? null
                                        : () => unawaited(
                                              _saveActiveListToLibrary(),
                                            ),
                                    caption: _showingLast
                                        ? '$parsedWordCount 个单词 · 按播放顺序对答案'
                                        : null,
                                    readOnly: _showingLast,
                                    overlayActionSize: cameraSize,
                                    overlayAlignment: _cameraAlignment,
                                    onOverlayAlignmentChanged:
                                        _handleCameraMoved,
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
                      AppToast(
                        toast: _toast.toast,
                        onActionPressed: _toast.hide,
                      ),
                    ],
                  ),
                ),
                if (!keyboardOpen) _buildBottomPanel(parsedWordCount),
              ],
            ),
          ),
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
    final wide = MediaQuery.sizeOf(context).width >= 600;

    // 图标不带字，长按 / 悬停给个名字。语义标签由按钮自己报，这里不重复。
    Widget headerAction(IconData icon, String label, VoidCallback onPressed) {
      return Padding(
        padding: const EdgeInsets.only(left: Spacing.xs),
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: AppIconButton(
            icon: icon,
            onPressed: onPressed,
            semanticLabel: label,
          ),
        ),
      );
    }

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
              // 320px + 放大字号时标题会差几个像素，裁掉半个「写」。
              // Alice / 听写 按一个字标整体缩，不换行。
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                  // 整个胶囊就是取消按钮。此前识别中没有任何出口 ——
                  // 网络挂住时只能等（现在有 60s 超时，但那也太久了）。
                  child: Semantics(
                    button: true,
                    label: '取消识别',
                    child: GestureDetector(
                      onTap: () {
                        _ocr.cancel();
                        _toast.show(kOcrCancelled);
                      },
                      behavior: HitTestBehavior.opaque,
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
                            const SizedBox(width: Spacing.xs),
                            Icon(
                              AppIcons.close,
                              size: 14,
                              color: colors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: Spacing.sm),
              // 入口按使用频率排：词库、收藏最常用，窄屏上也直接露着；
              // 错词本、历史、设置在窄屏收进菜单 —— 五个图标并排会把标题挤没，
              // 识别中的取消胶囊也没处放。够宽（平板 / Web）就全部平铺，
              // 为三四个入口再弹一层抽屉不值当。
              headerAction(AppIcons.library, '词库', _openLibrary),
              headerAction(AppIcons.starOutline, '收藏', _openFavorites),
              if (wide) ...[
                headerAction(AppIcons.wrongWords, '错词本', _openWrongWords),
                headerAction(AppIcons.time, '历史记录', _openHistory),
                headerAction(AppIcons.settings, '设置', _openSettings),
              ] else
                headerAction(AppIcons.menu, '菜单', _openMenu),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(int parsedWordCount) {
    final colors = context.colors;
    final start =
        parsedWordCount == 0 ? 0 : min(_startIndex, parsedWordCount - 1);

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
            // 起点不在开头时，按钮报的是这一轮真正要听的词数。
            wordCount: parsedWordCount - start,
            startOrdinal: start > 0 ? start + 1 : null,
            busy: _starting,
          ),
        ),
      ),
    );
  }
}

/// 「当前词表 / 上次听写」。上次听写空着或和草稿一样时整条不出现。
class _ListSourceSwitch extends StatelessWidget {
  const _ListSourceSwitch({
    required this.showingLast,
    required this.onChanged,
  });

  final bool showingLast;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: _SourceChip(
              label: '当前词表',
              selected: !showingLast,
              onTap: () => onChanged(false),
              colors: colors,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: _SourceChip(
              label: '上次听写',
              selected: showingLast,
              onTap: () => onChanged(true),
              colors: colors,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.primarySoft : colors.surface,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(
              color: selected ? colors.primary : colors.borderSubtle,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? colors.primary : colors.muted,
            ),
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
              const SizedBox(height: 2),
              Text(
                '免费',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? colors.primary : colors.subtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
