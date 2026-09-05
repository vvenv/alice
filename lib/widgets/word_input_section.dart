import 'package:flutter/material.dart';

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
    required this.onSetSample,
    required this.onClear,
    required this.startIndex,
    required this.onStartIndexChanged,
    required this.isDisplayMode,
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
  final VoidCallback onSetSample;
  final VoidCallback onClear;
  final int startIndex;
  final ValueChanged<int> onStartIndexChanged;
  final bool isDisplayMode;

  /// 浮在卡片右下角的操作按钮（首页放的是拍照识词）。
  ///
  /// 挂在卡片上而不是挂在整个区域上：编辑模式下方还有「共 N 个单词 / 示例 /
  /// 清空」那一行，按卡片定位才不用去猜那行有多高。
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

  @override
  void didUpdateWidget(WordInputSection oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    entries.removeAt(index);
    widget.onChanged(entries.map(entryToLine).join('\n'));

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
    final colors = context.colors;
    final parsedWords = parseWords(widget.value);
    final wordCount = parsedWords.length;
    final effectiveDisplayMode = widget.isDisplayMode && wordCount > 0;

    final overlayAction = widget.overlayAction;
    final card = effectiveDisplayMode
        ? _buildDisplayList(context, parsedWords)
        : _buildTextArea(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: overlayAction == null
              ? card
              : Stack(
                  children: [
                    Positioned.fill(child: card),
                    Positioned.fill(child: _buildOverlay(overlayAction)),
                  ],
                ),
        ),
        if (!effectiveDisplayMode) ...[
          const SizedBox(height: Spacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '共 $wordCount 个单词',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
              Row(
                children: [
                  AppButton(
                    label: '示例',
                    size: ButtonSize.sm,
                    onPressed: widget.onSetSample,
                  ),
                  const SizedBox(width: Spacing.sm),
                  AppButton(
                    label: '清空',
                    size: ButtonSize.sm,
                    onPressed: widget.onClear,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTextArea(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: colors.border),
      ),
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
          hintText: '每行一个单词或词组\n例：apple\nactor / actress',
          hintStyle:
              TextStyle(fontSize: 16, height: 22 / 16, color: colors.subtle),
        ),
      ),
    );
  }

  Widget _buildDisplayList(BuildContext context, List<String> parsedWords) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: EdgeInsets.only(
          top: Spacing.sm,
          bottom: Spacing.sm + _overlayBand,
        ),
        itemCount: parsedWords.length,
        itemBuilder: (context, idx) {
          final line = parsedWords[idx];
          final isCursor = idx == widget.startIndex;
          final entry = parseWordLine(line);
          final senses = entry.hasMeta
              ? splitSenses(entry.meaning ?? '', entry.pos)
              : const <String>[];
          final clampable = sensesClamped(senses, 2, 20);
          final expanded = _expanded.contains(idx);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.onStartIndexChanged(idx);
              if (clampable) _toggleExpand(idx);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.md,
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
                            color:
                                isCursor ? colors.primary : colors.foreground,
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
                  Semantics(
                    button: true,
                    label: '删除 ${entry.word}',
                    child: GestureDetector(
                      onTap: () => _handleDeleteWord(idx),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.xs),
                        child: Icon(
                          AppIcons.closeCircle,
                          size: 20,
                          color: colors.subtle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
