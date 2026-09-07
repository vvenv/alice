import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/storage.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_bottom_sheet.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'confirm_dialog.dart';

/// 错词本抽屉。
///
/// 累计错词本一直是持久化、跨轮次的，却只有听写页里那块被压到 88~120px 的
/// 面板能看到它 —— 「昨天错的词今天再听一遍」必须先随便开一轮听写。
/// 这里把它搬到首页菜单：查看、逐个划掉、导出，以及直接拿它开一轮听写。
Future<void> showWrongWordsDrawer(
  BuildContext context, {
  required ValueChanged<List<String>> onStartDictation,
  required ValueChanged<String> onMessage,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (sheetContext) => _WrongWordsDrawerBody(
      onStartDictation: onStartDictation,
      onMessage: onMessage,
    ),
  );
}

class _WrongWordsDrawerBody extends StatefulWidget {
  const _WrongWordsDrawerBody({
    required this.onStartDictation,
    required this.onMessage,
  });

  final ValueChanged<List<String>> onStartDictation;
  final ValueChanged<String> onMessage;

  @override
  State<_WrongWordsDrawerBody> createState() => _WrongWordsDrawerBodyState();
}

class _WrongWordsDrawerBodyState extends State<_WrongWordsDrawerBody> {
  late List<String> _words = loadWrongWords();

  Future<void> _remove(String word) async {
    setState(() => _words = _words.where((w) => w != word).toList());
    await removeWrongWordsFromBook([word]);
  }

  Future<void> _clear() async {
    final count = _words.length;
    if (count == 0) return;

    final confirmed = await showConfirmDialog(
      context,
      title: '清空错词本',
      message: '确定要清空这 $count 个错词吗？此操作不可撤销。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _words = <String>[]);
    await clearWrongWordsBook();
    widget.onMessage('已清空错词本');
  }

  Future<void> _export() async {
    if (_words.isEmpty) {
      widget.onMessage('暂无错词可导出');
      return;
    }
    await Clipboard.setData(ClipboardData(text: _words.join('\n')));
    widget.onMessage('已复制 ${_words.length} 个错词');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '错词本 (${_words.length})',
                  style: TextStyle(
                    fontFamily: AppFonts.displayZh,
                    fontSize: 17,
                    color: colors.foreground,
                  ),
                ),
              ),
              AppButton(
                label: '导出',
                variant: ButtonVariant.ghost,
                size: ButtonSize.sm,
                onPressed: _export,
              ),
              const SizedBox(width: Spacing.xs),
              AppButton(
                label: '清空',
                variant: ButtonVariant.ghost,
                size: ButtonSize.sm,
                onPressed: _clear,
              ),
            ],
          ),
        ),
        if (_words.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(Radii.surface),
            ),
            child: Text(
              '尚无错词。听写时标记的错词会攒在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.subtle),
            ),
          )
        else ...[
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final word in _words)
                    _WrongWordChip(word: word, onRemove: () => _remove(word)),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            '点词右侧的 × 表示已经掌握，把它从错词本划掉。',
            style: TextStyle(fontSize: 12, color: colors.subtle),
          ),
          const SizedBox(height: Spacing.md),
          AppButton(
            label: '听写错词 (${_words.length})',
            icon: AppIcons.play,
            variant: ButtonVariant.primary,
            onPressed: () {
              final words = _words;
              Navigator.of(context).pop();
              widget.onStartDictation(words);
            },
            width: double.infinity,
          ),
        ],
      ],
    );
  }
}

class _WrongWordChip extends StatelessWidget {
  const _WrongWordChip({required this.word, required this.onRemove});

  final String word;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.xs,
        top: Spacing.xs,
        bottom: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: colors.borderMuted),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            word,
            style: TextStyle(fontSize: 14, color: colors.foreground),
          ),
          const SizedBox(width: Spacing.xs),
          Semantics(
            button: true,
            label: '从错词本移除 $word',
            child: GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  AppIcons.closeCircle,
                  size: 16,
                  color: colors.subtle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
