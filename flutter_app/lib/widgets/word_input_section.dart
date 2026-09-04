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
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onSetSample;
  final VoidCallback onClear;
  final int startIndex;
  final ValueChanged<int> onStartIndexChanged;
  final bool isDisplayMode;

  @override
  State<WordInputSection> createState() => _WordInputSectionState();
}

class _WordInputSectionState extends State<WordInputSection> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final Set<int> _expanded = <int>{};

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: effectiveDisplayMode
              ? _buildDisplayList(context, parsedWords)
              : _buildTextArea(context),
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
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
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
