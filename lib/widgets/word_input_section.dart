import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/dictation.dart';
import '../services/dictionary.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_button.dart';
import 'app_icons.dart';

/// 单词列表区域：展示模式（逐条列表 + 释义 + 删除）与编辑模式（多行输入框）。
///
/// 对应 RN 版 src/components/WordInputSection.tsx。
class WordInputSection extends StatefulWidget {
  const WordInputSection({
    super.key,
    required this.value,
    required this.onChanged,
    required this.startIndex,
    required this.onStartIndexChanged,
    required this.isDisplayMode,
    this.onToggleDisplayMode,
    this.onWordDeleted,
    this.onClearAll,
    this.overlayAction,
    this.overlayActionSize = 0,
    this.overlayAlignment = Alignment.bottomRight,
    this.onOverlayAlignmentChanged,
  }) : assert(
          overlayAction == null || overlayActionSize > 0,
          'overlayAction 要给出边长，列表才知道底部该让出多少',
        );

  final String value;
  final ValueChanged<String> onChanged;
  final int startIndex;
  final ValueChanged<int> onStartIndexChanged;
  final bool isDisplayMode;

  /// 有词之后卡片自己带「完成 / 编辑」。空卡片不出现，避免先看见一条空工具栏。
  final VoidCallback? onToggleDisplayMode;

  /// 删掉某一行之后回调（行号 + 原文），供上层给一次撤销。
  ///
  /// 左滑或点 ✕ 都会删，误删代价不小 —— 刚 OCR 识出来三十个词，
  /// 误删一个就得重拍。
  final void Function(int index, String line)? onWordDeleted;

  /// 「清空」被点击。清空本身由上层执行，好把撤销一并给了。
  final VoidCallback? onClearAll;

  /// 浮在卡片上的操作按钮（首页放的是拍照识词）。
  final Widget? overlayAction;

  /// [overlayAction] 的边长，列表照它让出底部空间。
  final double overlayActionSize;

  /// [overlayAction] 停在卡片里的哪个位置，-1 ~ 1。
  final Alignment overlayAlignment;

  /// 用户把 [overlayAction] 拖到新位置、并且松手之后回调。
  ///
  /// 拖动过程中的位置由本 widget 自己拿着，不往上抛 —— 上层只关心最终落点，
  /// 不用为每一帧的位移重建整棵树、也不用为每一帧写一次存储。
  /// 传 null 就是不允许拖。
  final ValueChanged<Alignment>? onOverlayAlignmentChanged;

  @override
  State<WordInputSection> createState() => _WordInputSectionState();
}

class _WordInputSectionState extends State<WordInputSection> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final Set<int> _expanded = <int>{};

  /// 拖动中的临时落点，松手后清空、改用 [WordInputSection.overlayAlignment]。
  Alignment? _dragAlignment;

  final ScrollController _listScroll = ScrollController();
  final GlobalKey _cursorKey = GlobalKey();

  /// 用户刚亲手点成起点的那一行。它就在手指底下，哪怕只露了半行也别去挪。
  int? _tappedIndex;

  @override
  void initState() {
    super.initState();
    // 冷启动恢复出来的起点多半在第一屏之外。
    if (widget.startIndex > 0) _revealCursor();
  }

  /// 把起点那一行滚进视野，已经完整露着就不动。
  ///
  /// 行高不固定（释义长短不一），列表又是懒构建的，目标行可能还没有
  /// RenderObject。先按比例跳到大概的位置，等它建出来再精确对齐；
  /// 懒列表的总长是估的，跳一次未必够，所以留几次重试。
  void _revealCursor({int attempts = 6}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listScroll.hasClients) return;
      final position = _listScroll.position;
      final target = _cursorKey.currentContext?.findRenderObject();

      if (target != null) {
        final viewport = RenderAbstractViewport.of(target);
        final top = viewport.getOffsetToReveal(target, 0).offset;
        final bottom = viewport.getOffsetToReveal(target, 1).offset;
        // top 是「把它顶到视口上沿」的偏移，bottom 是「贴到下沿」的偏移；
        // 当前偏移落在两者之间就是完整可见。
        if (position.pixels <= top && position.pixels >= bottom) return;
        // 停在上方三分之一处：前面留一两行上下文，后面要听的词看得更多。
        final wanted = viewport.getOffsetToReveal(target, 0.3).offset;
        _listScroll.jumpTo(
          wanted.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
        return;
      }

      if (attempts == 0) return;
      final count = parseWords(widget.value).length;
      if (count < 2) return;
      _listScroll.jumpTo(
        position.maxScrollExtent * widget.startIndex / (count - 1),
      );
      _revealCursor(attempts: attempts - 1);
    });
  }

  @override
  void didUpdateWidget(WordInputSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tapped = _tappedIndex == widget.startIndex;
    _tappedIndex = null;
    if (!tapped &&
        (widget.startIndex != oldWidget.startIndex ||
            (widget.isDisplayMode && !oldWidget.isDisplayMode))) {
      _revealCursor();
    }
    // 外部改了文本（载入历史/词库、OCR 结果、补全）就同步进输入框，
    // 但用户正在打字时不要覆盖光标。
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _listScroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// [WordInputSection.overlayAction] 从卡片底边往上占掉的高度。
  ///
  /// 按钮停在底部时，列表要多让出这么多，否则滚到底时最后一词的删除按钮正好
  /// 压在按钮下面，永远点不到。按钮被拖上去之后这块空白就没用了，跟着一起收掉。
  ///
  /// 用的是松手后的落点而不是拖动中的实时位置 —— 否则列表的可滚动范围会在
  /// 手指底下一帧一帧地变，内容跟着抖。
  double get _overlayBand {
    if (widget.overlayAction == null) return 0;
    final atBottom = ((widget.overlayAlignment.y + 1) / 2).clamp(0.0, 1.0);
    return (_overlayMargin + widget.overlayActionSize) * atBottom;
  }

  /// 按钮离卡片边缘的留白。四边同一个值，所以默认的右下角是「右边和下边一样远」。
  static const double _overlayMargin = Spacing.md;

  /// 把一次拖动的位移换算成 [Alignment] 上的位移。
  ///
  /// Alignment 的 -1 ~ 1 铺在「卡片减掉两边留白、再减掉按钮自身」剩下的那块
  /// 活动范围上，所以除以的是 free 而不是卡片宽高。
  void _dragOverlayBy(Offset delta, Size cardSize) {
    final current = _dragAlignment ?? widget.overlayAlignment;
    final freeW =
        cardSize.width - _overlayMargin * 2 - widget.overlayActionSize;
    final freeH =
        cardSize.height - _overlayMargin * 2 - widget.overlayActionSize;

    setState(() {
      _dragAlignment = Alignment(
        freeW <= 0
            ? current.x
            : (current.x + 2 * delta.dx / freeW).clamp(-1.0, 1.0).toDouble(),
        freeH <= 0
            ? current.y
            : (current.y + 2 * delta.dy / freeH).clamp(-1.0, 1.0).toDouble(),
      );
    });
  }

  void _endOverlayDrag() {
    final landed = _dragAlignment;
    setState(() => _dragAlignment = null);
    if (landed != null) widget.onOverlayAlignmentChanged?.call(landed);
  }

  /// 卡片上那颗可拖的浮动按钮。
  Widget _buildOverlay(Widget action) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final draggable = widget.onOverlayAlignmentChanged != null;
        return Padding(
          padding: const EdgeInsets.all(_overlayMargin),
          child: Align(
            alignment: _dragAlignment ?? widget.overlayAlignment,
            child: draggable
                ? GestureDetector(
                    // 只认 pan：单击照旧落到 action 自己的 onTap 上，
                    // 手指动起来之后手势竞技场才把事件判给拖动。
                    onPanUpdate: (d) =>
                        _dragOverlayBy(d.delta, constraints.biggest),
                    onPanEnd: (_) => _endOverlayDrag(),
                    onPanCancel: _endOverlayDrag,
                    child: action,
                  )
                : action,
          ),
        );
      },
    );
  }

  void _toggleExpand(int idx) {
    setState(() {
      if (!_expanded.remove(idx)) _expanded.add(idx);
    });
  }

  void _handleDeleteWord(int index) {
    final entries = parseWordEntries(widget.value);
    if (index < 0 || index >= entries.length) return;
    final removed = entryToLine(entries.removeAt(index));
    widget.onChanged(entries.map(entryToLine).join('\n'));
    widget.onWordDeleted?.call(index, removed);

    // 删除后平移展开态索引，避免串到相邻词条
    setState(() {
      final next = <int>{};
      for (final i in _expanded) {
        if (i < index) {
          next.add(i);
        } else if (i > index) {
          next.add(i - 1);
        }
      }
      _expanded
        ..clear()
        ..addAll(next);
    });

    if (index < widget.startIndex) {
      widget.onStartIndexChanged(widget.startIndex - 1);
    } else if (index == widget.startIndex) {
      final maxIndex = entries.isEmpty ? 0 : entries.length - 1;
      widget.onStartIndexChanged(
        widget.startIndex < maxIndex ? widget.startIndex : maxIndex,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsedWords = parseWords(widget.value);
    final wordCount = parsedWords.length;
    final effectiveDisplayMode = widget.isDisplayMode && wordCount > 0;

    final overlayAction = widget.overlayAction;
    final card = _buildCard(
      context,
      wordCount: wordCount,
      raised: effectiveDisplayMode,
      child: effectiveDisplayMode
          ? _buildDisplayList(context, parsedWords)
          : _buildTextArea(context),
    );

    if (overlayAction == null) return card;
    return Stack(
      children: [
        Positioned.fill(child: card),
        Positioned.fill(child: _buildOverlay(overlayAction)),
      ],
    );
  }

  /// 词数和「完成 / 编辑」属于这张卡片，不另占页面上一行。
  Widget _buildCard(
    BuildContext context, {
    required int wordCount,
    required bool raised,
    required Widget child,
  }) {
    final colors = context.colors;
    final showChrome = wordCount > 0 && widget.onToggleDisplayMode != null;

    return Container(
      decoration: BoxDecoration(
        color: raised ? colors.surfaceRaised : colors.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: raised ? colors.borderSubtle : colors.border),
        boxShadow: raised
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showChrome)
            _buildCardChrome(context, wordCount: wordCount, display: raised),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildCardChrome(
    BuildContext context, {
    required int wordCount,
    required bool display,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.sm, 0),
      child: Row(
        children: [
          // 展示模式下点某一行会把它设为听写起点（那一行会高亮 + 左侧描边），
          // 但此前没有任何文字说明，光看高亮猜不出来。
          // 起点挪开之后，提示换成「从第几个开始」—— 学会了的人不用每次看说明。
          Expanded(
            child: Text(
              !display
                  ? '$wordCount 个单词'
                  : widget.startIndex > 0
                      ? '$wordCount 个单词 · 从第 ${widget.startIndex + 1} 个开始'
                      : '$wordCount 个单词 · 点词设为起点',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (widget.onClearAll != null) ...[
            AppButton(
              label: '清空',
              variant: ButtonVariant.ghost,
              size: ButtonSize.sm,
              onPressed: widget.onClearAll,
            ),
            const SizedBox(width: Spacing.xs),
          ],
          AppButton(
            label: display ? '编辑' : '完成',
            icon: display ? AppIcons.createOutline : AppIcons.checkmark,
            size: ButtonSize.sm,
            active: !display,
            onPressed: widget.onToggleDisplayMode,
          ),
        ],
      ),
    );
  }

  Widget _buildTextArea(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style:
            TextStyle(fontSize: 16, height: 22 / 16, color: colors.foreground),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          hintText: '每行一个单词或词组\n例：apple\nactor / actress\n或点右上角词库载入教材词表',
          hintStyle:
              TextStyle(fontSize: 16, height: 22 / 16, color: colors.subtle),
        ),
      ),
    );
  }

  Widget _buildDisplayList(BuildContext context, List<String> parsedWords) {
    final colors = context.colors;

    return ListView.builder(
      controller: _listScroll,
      padding: EdgeInsets.only(
        top: Spacing.sm,
        bottom: Spacing.sm + _overlayBand,
      ),
      itemCount: parsedWords.length,
      itemBuilder: (context, idx) {
        final line = parsedWords[idx];
        // 起点在开头时不高亮：第一行亮着看起来像「选中了」，其实什么也没选。
        final isCursor = idx == widget.startIndex && idx > 0;
        final entry = parseWordLine(line);
        final senses = entry.hasMeta
            ? splitSenses(entry.meaning ?? '', entry.pos)
            : const <String>[];
        final clampable = sensesClamped(senses, 2, 20);
        final expanded = _expanded.contains(idx);

        final row = GestureDetector(
          key: idx == widget.startIndex ? _cursorKey : null,
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _tappedIndex = idx;
            widget.onStartIndexChanged(idx);
            if (clampable) _toggleExpand(idx);
          },
          child: Container(
            // 右侧少留一点：✕ 的 40px 点击区自带留白。
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.sm,
              Spacing.md,
            ),
            decoration: BoxDecoration(
              color: isCursor ? colors.primarySoft : null,
              border: Border(
                bottom: BorderSide(color: colors.borderMuted, width: 0.5),
                left: BorderSide(
                  color: isCursor ? colors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    (idx + 1).toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontFamily: AppFonts.serif,
                      fontSize: 13,
                      color: isCursor ? colors.primary : colors.subtle,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.word,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isCursor ? colors.primary : colors.foreground,
                        ),
                      ),
                      if (entry.hasMeta) ...[
                        const SizedBox(height: 2),
                        Text(
                          senses.join('\n'),
                          maxLines: expanded ? null : 2,
                          overflow: expanded
                              ? TextOverflow.clip
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 17 / 12,
                            color: colors.subtle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                // 每行一颗深色 ✕ 曾是整页最抢眼的东西。压淡、点击区放大到
                // 40；主要的删法是左滑，✕ 被拍照按钮挡住时也删得掉。
                Semantics(
                  button: true,
                  label: '删除 ${entry.word}',
                  child: GestureDetector(
                    onTap: () => _handleDeleteWord(idx),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        AppIcons.close,
                        size: 18,
                        color: colors.subtle.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return Dismissible(
          // 行号进 key：删掉一行后后面的行整体前移，旧的滑动状态不能串过去。
          key: ValueKey('$idx|$line'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _handleDeleteWord(idx),
          background: Container(
            color: colors.dangerSoft,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: Spacing.xl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.trash, size: 18, color: colors.danger),
                const SizedBox(width: Spacing.xs),
                Text(
                  '删除',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.danger,
                  ),
                ),
              ],
            ),
          ),
          child: row,
        );
      },
    );
  }
}
