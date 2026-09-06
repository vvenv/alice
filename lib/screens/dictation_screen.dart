import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/dictation.dart';
import '../services/dictionary.dart';
import '../services/haptics.dart';
import '../services/sound.dart';
import '../services/storage.dart';
import '../state/playback_controller.dart';
import '../state/toast_controller.dart';
import '../state/wrong_words_controller.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/playback_controls.dart';

/// 圆盘让位给「标记错词」时能缩到的下限 —— 再小单词就看不清了。
const double _minDialSize = 140;

/// 听写页。对应 RN 版 src/screens/DictationScreen.tsx。
class DictationScreen extends StatefulWidget {
  const DictationScreen({
    super.key,
    required this.words,
    required this.intervalSec,
    required this.autoNext,
  });

  final List<String> words;
  final double intervalSec;
  final bool autoNext;

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen>
    with TickerProviderStateMixin {
  late final PlaybackController _playback = PlaybackController(
    intervalSec: widget.intervalSec,
    autoNext: widget.autoNext,
  );
  late final WrongWordsController _wrong = WrongWordsController();
  late final ToastController _toast = ToastController();

  late double _intervalSec = widget.intervalSec;
  late bool _autoNext = widget.autoNext;

  bool _showWord = false;
  bool _metaExpanded = false;
  int? _elapsedSec;
  DateTime _startTime = DateTime.now();

  // 顶部进度条：词与词之间平滑过渡，而不是跳变。
  late final AnimationController _progressAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late Animation<double> _progressTween =
      const AlwaysStoppedAnimation<double>(0);
  double _progressValue = 0;

  // 倒计时环：每段用一条线性动画驱动，让它以 60fps 匀速耗尽，
  // 而不是跟着调度器每 50ms 的 tick 重绘。
  late final AnimationController _countdownAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1),
  );

  late final AnimationController _finishAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  int? _prevRemainingMs;
  int? _prevTickMs;
  int _prevIndex = 0;

  @override
  void initState() {
    super.initState();
    _playback.addListener(_onPlaybackChanged);
    _wrong.addListener(_onControllerChanged);
    _toast.addListener(_onControllerChanged);
    // 等转场结束再开口。第一帧就朗读，iOS 会把第一句吃掉；
    // 点暂停再继续之所以能出声，是因为那时页面已经停稳了。
    // 不是在等单词音频下载 —— 下载仍然不挡播放。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startWhenRouteReady());
    });
  }

  Future<void> _startWhenRouteReady() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      final done = Completer<void>();
      void listener(AnimationStatus status) {
        if ((status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed) &&
            !done.isCompleted) {
          done.complete();
        }
      }

      animation.addStatusListener(listener);
      if (animation.status != AnimationStatus.completed &&
          animation.status != AnimationStatus.dismissed) {
        await done.future;
      }
      animation.removeStatusListener(listener);
    }
    if (!mounted) return;
    _playback.startDictation(widget.words);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onPlaybackChanged() {
    if (!mounted) return;

    _syncProgressBar();
    _syncCountdown();
    _syncTickSound();
    _syncFinished();

    // 切换单词时收起释义，避免上一词展开态污染下一词
    if (_playback.currentIndex != _prevIndex) {
      _prevIndex = _playback.currentIndex;
      _metaExpanded = false;
    }

    setState(() {});
  }

  void _syncProgressBar() {
    final total = _playback.wordList.length;
    final next = total > 0 ? (_playback.currentIndex + 1) / total : 0.0;
    if ((next - _progressValue).abs() < 0.0001) return;

    _progressTween = Tween<double>(begin: _progressValue, end: next).animate(
      CurvedAnimation(parent: _progressAnim, curve: Curves.easeOutCubic),
    );
    _progressValue = next;
    _progressAnim
      ..reset()
      ..forward();
  }

  void _syncCountdown() {
    final remaining = _playback.remainingMs;
    final prev = _prevRemainingMs;
    _prevRemainingMs = remaining;

    final intervalMs = (_intervalSec * 1000).round();

    if (remaining == null) {
      _countdownAnim.stop();
      _countdownAnim.duration = const Duration(milliseconds: 150);
      _countdownAnim.animateTo(0, curve: Curves.easeOutQuad);
      return;
    }

    // 值刚出现或变大 = 新一段的开始（下一个词、恢复播放，
    // 或者等待中拖动了间隔滑块）。
    if (prev == null || remaining > prev) {
      _countdownAnim.stop();
      _countdownAnim.value =
          intervalMs > 0 ? math.min(1, remaining / intervalMs) : 0;
      _countdownAnim.duration = Duration(milliseconds: remaining);
      _countdownAnim.animateTo(0, curve: Curves.linear);
    }
  }

  /// 每个词的倒计时进入最后一秒时的怀表滴答。
  void _syncTickSound() {
    final prev = _prevTickMs;
    final remaining = _playback.remainingMs;
    _prevTickMs = remaining;
    if (prev != null && remaining != null && prev > 1000 && remaining <= 1000) {
      playTick();
    }
  }

  /// 完成：只记一次统计，然后庆祝。
  void _syncFinished() {
    final isFinished =
        _playback.playState == PlayState.idle && _playback.wordList.isNotEmpty;
    if (!isFinished || _elapsedSec != null) return;

    final seconds =
        (DateTime.now().difference(_startTime).inMilliseconds / 1000).round();
    _elapsedSec = seconds < 1 ? 1 : seconds;
    Haptics.notifySuccess();
    playChime();
    _finishAnim
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _playback.removeListener(_onPlaybackChanged);
    _wrong.removeListener(_onControllerChanged);
    _toast.removeListener(_onControllerChanged);
    _playback.dispose();
    _wrong.dispose();
    _toast.dispose();
    _progressAnim.dispose();
    _countdownAnim.dispose();
    _finishAnim.dispose();
    super.dispose();
  }

  // --- 操作 ---------------------------------------------------------------

  void _handleIntervalChanged(double sec) {
    setState(() => _intervalSec = sec);
    _playback.setIntervalSec(sec);
    saveIntervalSec(sec);
  }

  void _handleAutoNextChanged(bool value) {
    setState(() => _autoNext = value);
    _playback.setAutoNext(value);
  }

  void _handlePlayToggle() {
    if (_playback.playState == PlayState.playing) {
      _playback.pauseDictation();
    } else {
      _playback.resumeDictation();
    }
  }

  bool get _markEnabled =>
      _playback.isActive && _playback.currentIndex < _playback.wordList.length;

  bool get _skipEnabled => _markEnabled;

  bool get _previousEnabled => _playback.isActive && _playback.currentIndex > 0;

  void _handleMarkWrong() {
    if (!_markEnabled) return;
    final word = speakTextFromEntry(_playback.wordList[_playback.currentIndex]);
    Haptics.notifyWarning();
    _wrong.markWrong(word);
  }

  void _handleSkip() {
    if (!_skipEnabled) return;
    Haptics.tapLight();
    _playback.skipToNextWord();
  }

  void _handlePrevious() {
    if (!_previousEnabled) return;
    Haptics.tapLight();
    _playback.goToPreviousWord();
  }

  void _handleExit() => Navigator.of(context).pop();

  /// 中途退出要确认；已结束则直接返回。
  Future<void> _requestStop() async {
    if (!_playback.isActive) {
      _handleExit();
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '结束听写',
      message: '当前听写尚未完成，确定要结束并返回吗？',
      confirmLabel: '结束',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _playback.stopDictation();
    _handleExit();
  }

  Future<void> _handleExport() async {
    final msg = await _wrong.exportWrong();
    if (msg.isNotEmpty) _toast.show(msg);
  }

  void _handleClearWrong() {
    if (_wrong.wrongWords.isEmpty) return;
    _wrong.clearWrong();
    _toast.show('已清空错词本');
  }

  void _handleRemoveWrongWord(String word) {
    _wrong.removeWrongWord(word);
    _toast.show(
      '已移除 $word',
      action: ToastAction(
        label: '撤销',
        onPressed: () => _wrong.restoreWrongWord(word),
      ),
    );
  }

  /// 只重听标记为错的词；如果当前列表里还留着补全过的整行，就用那一行。
  void _handleRetryWrong() {
    final wrongWords = _wrong.wrongWords;
    if (wrongWords.isEmpty) return;

    final lines = wrongWords.map((w) {
      for (final line in _playback.wordList) {
        if (speakTextFromEntry(line) == w) return line;
      }
      return w;
    }).toList();

    setState(() {
      _elapsedSec = null;
      _showWord = false;
      _startTime = DateTime.now();
    });
    _finishAnim.reset();
    _playback.startDictation(lines);
  }

  // --- 渲染 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    final useDualPane = width >= 768 || (width >= 700 && width > height);
    final useCompactLayout = !useDualPane && height < 900;

    final dialSize = math
        .max(
          useCompactLayout ? 200.0 : 220.0,
          math.min(
            useCompactLayout ? 260.0 : 300.0,
            math.min(
              width * (useDualPane ? 0.36 : 0.8),
              height * (useCompactLayout ? 0.38 : 0.48),
            ),
          ),
        )
        .roundToDouble();

    final isFinished =
        _playback.playState == PlayState.idle && _playback.wordList.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestStop();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildProgressBar(colors),
                  _buildHeader(colors, isFinished),
                  Expanded(
                    child: useDualPane
                        ? Row(
                            children: [
                              Expanded(
                                child: _buildWordStage(
                                  colors,
                                  dialSize,
                                  useCompactLayout,
                                  isFinished,
                                ),
                              ),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: math.min(380, width * 0.42),
                                ),
                                child: _buildBottomPanel(
                                  colors,
                                  useCompactLayout: useCompactLayout,
                                  useDualPane: true,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: _buildWordStage(
                                  colors,
                                  dialSize,
                                  useCompactLayout,
                                  isFinished,
                                ),
                              ),
                              _buildBottomPanel(
                                colors,
                                useCompactLayout: useCompactLayout,
                                useDualPane: false,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
              AppToast(toast: _toast.toast, onActionPressed: _toast.hide),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(AppColors colors) {
    return SizedBox(
      height: 4,
      child: Semantics(
        label: '听写进度',
        value:
            '${math.min(_playback.currentIndex + 1, _playback.wordList.length)}'
            ' / ${_playback.wordList.length}',
        child: Container(
          color: colors.track,
          child: AnimatedBuilder(
            animation: _progressTween,
            builder: (context, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _progressTween.value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.gold,
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors, bool isFinished) {
    // 两侧留一样宽，中间的计数才在正中；系统字号放大后状态胶囊会变宽，
    // 这里跟着放大，否则「听写中」会被裁掉。
    final sideWidth = MediaQuery.textScalerOf(context).scale(80);

    final status = isFinished
        ? ('已完成', kStatusPlaying)
        : _playback.playState == PlayState.playing
            ? ('听写中', kStatusPlaying)
            : ('已暂停', colors.gold);

    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.md,
        bottom: Spacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: sideWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppIconButton(
                icon: AppIcons.close,
                onPressed: _requestStop,
                semanticLabel: '退出听写',
              ),
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${_playback.currentIndex + 1}',
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 17,
                  ),
                ),
                const TextSpan(text: ' / '),
                TextSpan(text: '${_playback.wordList.length}'),
              ],
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: colors.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(
            width: sideWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                label: status.$1,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.full),
                    border: Border.all(color: colors.borderMuted),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: status.$2,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Spacing.xs + 2),
                      Text(
                        status.$1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordStage(
    AppColors colors,
    double dialSize,
    bool useCompactLayout,
    bool isFinished,
  ) {
    final gap = useCompactLayout ? Spacing.sm : Spacing.lg;

    final padding = EdgeInsets.symmetric(
      horizontal: Spacing.lg,
      vertical: useCompactLayout ? Spacing.xs : Spacing.md,
    );

    // 完成卡片自带滚动，直接居中就行。
    if (isFinished) {
      return Padding(
        padding: padding,
        child: Center(child: _buildFinished(colors)),
      );
    }

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // dialSize 是按整块屏幕估的；真机上进度条、页头、底部面板和安全区
          // 吃掉高度之后，舞台能用的比那个小 —— 圆盘先让位，别把按钮挤出去。
          final markSlot = MediaQuery.textScalerOf(context)
              .scale(buttonMinHeight(ButtonSize.sm));
          final fittedDial = math.max(
            _minDialSize,
            math.min(dialSize, constraints.maxHeight - gap - markSlot),
          );

          // 圆盘缩到下限还是放不下（超大系统字号）时让舞台滚动，
          // 而不是把「标记错词」裁掉半截。
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildWatch(colors, fittedDial),
                    SizedBox(height: gap),
                    AppButton(
                      label: '标记错词',
                      icon: AppIcons.closeCircleOutline,
                      variant: ButtonVariant.danger,
                      size: ButtonSize.sm,
                      onPressed: _handleMarkWrong,
                      disabled: !_markEnabled,
                      haptic: false,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWatch(AppColors colors, double dialSize) {
    final dialInner = dialSize - 7 * 2 - 24;

    return SizedBox(
      width: dialSize,
      height: dialSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          CountdownRing(
            size: dialSize,
            strokeWidth: 7,
            progress: _countdownAnim,
            color: colors.gold,
            trackColor: colors.track,
            ticks: 12,
            tickColor: colors.borderMuted,
            child: _buildDial(colors, dialInner),
          ),
          Positioned(
            top: 0,
            right: 12,
            child: AppIconButton(
              icon: _showWord ? AppIcons.eye : AppIcons.eyeOff,
              onPressed: () => setState(() => _showWord = !_showWord),
              semanticLabel: _showWord ? '隐藏单词' : '显示单词',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDial(AppColors colors, double dialInner) {
    final hasWord = _playback.currentIndex < _playback.wordList.length;
    final currentLine =
        hasWord ? _playback.wordList[_playback.currentIndex] : '';
    final entry = parseWordLine(currentLine);
    final senses = entry.meaning != null
        ? splitSenses(entry.meaning!, entry.pos)
        : const <String>[];
    final meaningHasMore = sensesClamped(senses, 2, 14);

    final countdownLabel = _playback.remainingMs != null
        ? '${(_playback.remainingMs! / 1000).toStringAsFixed(1)}s'
        : '—';
    final countdownVisible =
        _playback.isActive && _autoNext && _playback.remainingMs != null;

    return GestureDetector(
      // 表盘左滑标记错词，右滑跳过 —— 与 RN 版的 PanResponder 一致。
      onHorizontalDragEnd: (details) {
        if (!_markEnabled && !_skipEnabled) return;
        final vx = details.velocity.pixelsPerSecond.dx;
        if (vx.abs() < 200) return;
        if (vx < 0) {
          _handleMarkWrong();
        } else {
          _handleSkip();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: '听写表盘',
        hint: '向左滑标记错词，向右滑跳过',
        child: Container(
          width: dialInner,
          height: dialInner,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
          decoration: BoxDecoration(
            color:
                _wrong.markedFlash ? colors.dangerSoft : colors.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(
              color: _wrong.markedFlash ? colors.danger : colors.borderSubtle,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showWord && hasWord) ...[
                Text(
                  entry.word,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 36,
                    letterSpacing: 1,
                    color: colors.foreground,
                  ),
                ),
                if (entry.hasMeta) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    senses.join('\n'),
                    textAlign: TextAlign.center,
                    maxLines: _metaExpanded ? null : 2,
                    overflow: _metaExpanded
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: colors.muted,
                    ),
                  ),
                  if (meaningHasMore)
                    Semantics(
                      button: true,
                      label: _metaExpanded ? '收起释义' : '展开全部释义',
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _metaExpanded = !_metaExpanded),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _metaExpanded ? '收起' : '展开全部',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colors.muted,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                _metaExpanded
                                    ? AppIcons.chevronUp
                                    : AppIcons.chevronDown,
                                size: 11,
                                color: colors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ] else
                Text(
                  '•••••',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 36,
                    letterSpacing: 1,
                    color: colors.foreground,
                  ),
                ),
              if (_showWord &&
                  !_metaExpanded &&
                  _playback.currentIndex + 1 < _playback.wordList.length) ...[
                const SizedBox(height: Spacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '下一个',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      parseWordLine(
                        _playback.wordList[_playback.currentIndex + 1],
                      ).word,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.subtle,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Spacing.sm),
              Opacity(
                opacity: countdownVisible ? 1 : 0,
                child: Text(
                  countdownLabel,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 14,
                    color: colors.gold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinished(AppColors colors) {
    final wrongCount = _wrong.wrongWords.length;
    final elapsed = _elapsedSec;

    return AnimatedBuilder(
      animation: _finishAnim,
      builder: (context, child) {
        final t =
            Curves.elasticOut.transform(_finishAnim.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: _finishAnim.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        );
      },
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 320, minHeight: 240),
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    AppIcons.checkmarkCircle,
                    size: 48,
                    color: kStatusPlaying,
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    '听写完成',
                    style: TextStyle(
                      fontFamily: AppFonts.displayZh,
                      fontSize: 22,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: Spacing.md + Spacing.xs),
                  Container(
                    padding: const EdgeInsets.only(
                      top: Spacing.lg,
                      left: Spacing.lg,
                      right: Spacing.lg,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colors.borderMuted, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        _statItem(
                          colors,
                          '${_playback.wordList.length}',
                          '单词',
                          colors.foreground,
                        ),
                        _statItem(
                          colors,
                          '$wrongCount',
                          '错词',
                          wrongCount > 0 ? colors.danger : colors.foreground,
                        ),
                        _statItem(
                          colors,
                          elapsed != null
                              ? '${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}'
                              : '—',
                          '用时',
                          colors.foreground,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xxl),
            if (wrongCount > 0) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AppButton(
                  label: '错词再听一遍 ($wrongCount)',
                  icon: AppIcons.refresh,
                  variant: ButtonVariant.primary,
                  onPressed: _handleRetryWrong,
                  width: double.infinity,
                ),
              ),
              const SizedBox(height: Spacing.xxl),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AppButton(
                label: '返回首页',
                icon: AppIcons.arrowBack,
                variant: wrongCount > 0
                    ? ButtonVariant.outline
                    : ButtonVariant.primary,
                onPressed: _handleExit,
                width: double.infinity,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(AppColors colors, String value, String label, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 22,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(
    AppColors colors, {
    required bool useCompactLayout,
    required bool useDualPane,
  }) {
    final gap = useCompactLayout ? Spacing.md : Spacing.lg;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: useDualPane
            ? Border(left: BorderSide(color: colors.borderSubtle))
            : Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: useDualPane
            ? Spacing.xl
            : (useCompactLayout ? Spacing.md : Spacing.lg),
        bottom: useCompactLayout ? Spacing.sm : Spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlaybackControls(
            intervalSec: _intervalSec,
            autoNext: _autoNext,
            onIntervalChanged: _handleIntervalChanged,
            onAutoNextChanged: _handleAutoNextChanged,
            showPlayButton: false,
          ),
          SizedBox(height: gap),
          _buildControlRow(colors),
          SizedBox(height: gap),
          Flexible(
            child: _buildWrongSection(
              colors,
              useCompactLayout: useCompactLayout,
              useDualPane: useDualPane,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlRow(AppColors colors) {
    Widget item(
      IconData icon,
      String label,
      double size,
      IconButtonVariant variant,
      VoidCallback onPressed, {
      bool disabled = false,
      bool haptic = true,
      bool side = true,
    }) {
      return Padding(
        padding: EdgeInsets.only(top: side ? 8 : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              icon: icon,
              size: size,
              variant: variant,
              onPressed: onPressed,
              disabled: disabled,
              haptic: haptic,
              semanticLabel: label,
            ),
            const SizedBox(height: Spacing.xs + 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.muted,
              ),
            ),
          ],
        ),
      );
    }

    final playing = _playback.playState == PlayState.playing;

    // 间距均分而不是写死 —— 系统字号放大后文字变宽，写死会撑破一行。
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(
          AppIcons.stop,
          '结束',
          48,
          IconButtonVariant.danger,
          _requestStop,
          disabled: !_playback.isActive,
        ),
        item(
          AppIcons.skipBack,
          '上一个',
          48,
          IconButtonVariant.surface,
          _handlePrevious,
          disabled: !_previousEnabled,
          haptic: false,
        ),
        item(
          playing ? AppIcons.pause : AppIcons.play,
          playing ? '暂停' : '继续',
          64,
          IconButtonVariant.primary,
          _handlePlayToggle,
          side: false,
        ),
        item(
          AppIcons.skipForward,
          '下一个',
          48,
          IconButtonVariant.surface,
          _handleSkip,
          disabled: !_skipEnabled,
          haptic: false,
        ),
      ],
    );
  }

  Widget _buildWrongSection(
    AppColors colors, {
    required bool useCompactLayout,
    required bool useDualPane,
  }) {
    final words = _wrong.wrongWords;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '错词本 (${words.length})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.muted,
              ),
            ),
            Row(
              children: [
                AppButton(
                  label: '导出',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.sm,
                  onPressed: _handleExport,
                ),
                const SizedBox(width: Spacing.sm),
                AppButton(
                  label: '清空',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.sm,
                  onPressed: _handleClearWrong,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Flexible(
          child: words.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.surface),
                  ),
                  child: Text(
                    '尚无错词',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.subtle),
                  ),
                )
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    children: [
                      for (final word in words)
                        _WrongChip(
                          word: word,
                          onTap: () => _handleRemoveWrongWord(word),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );

    if (useDualPane) return content;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: useCompactLayout ? 88 : 120),
      child: content,
    );
  }
}

class _WrongChip extends StatelessWidget {
  const _WrongChip({required this.word, required this.onTap});

  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: '移除错词 $word',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(color: colors.borderMuted),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word,
                style: TextStyle(fontSize: 13, color: colors.foreground),
              ),
              const SizedBox(width: 4),
              Text(
                '×',
                style: TextStyle(fontSize: 14, color: colors.subtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
