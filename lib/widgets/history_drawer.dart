import 'package:flutter/material.dart';

import '../models/word_history_entry.dart';
import '../services/dictation.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_bottom_sheet.dart';
import 'app_icons.dart';
import 'drawer_search_field.dart';

/// 历史记录抽屉。对应 RN 版 src/components/HistoryDrawer.tsx。
Future<void> showHistoryDrawer(
  BuildContext context, {
  required List<WordHistoryEntry> history,
  required List<String> favorites,
  required ValueChanged<WordHistoryEntry> onApply,
  required ValueChanged<String> onDelete,
  required VoidCallback onClear,
  required ValueChanged<String> onToggleFavorite,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (sheetContext) => _HistoryDrawerBody(
      history: history,
      initialFavorites: favorites,
      onApply: onApply,
      onDelete: onDelete,
      onClear: onClear,
      onToggleFavorite: onToggleFavorite,
    ),
  );
}

int _wordCount(String text) => parseWords(text).length;

class _HistoryDrawerBody extends StatefulWidget {
  const _HistoryDrawerBody({
    required this.history,
    required this.initialFavorites,
    required this.onApply,
    required this.onDelete,
    required this.onClear,
    required this.onToggleFavorite,
  });

  final List<WordHistoryEntry> history;
  final List<String> initialFavorites;
  final ValueChanged<WordHistoryEntry> onApply;
  final ValueChanged<String> onDelete;
  final VoidCallback onClear;
  final ValueChanged<String> onToggleFavorite;

  @override
  State<_HistoryDrawerBody> createState() => _HistoryDrawerBodyState();
}

/// 搜索框出现的门槛。条目少的时候它只是噪音；历史上限 50 条，多起来
/// 只能一路滚。
const int _searchThreshold = 6;

class _HistoryDrawerBodyState extends State<_HistoryDrawerBody> {
  late final Set<String> _favorites = widget.initialFavorites.toSet();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 按词表正文匹配 —— 用户记得的是「那份有 elephant 的词表」。
  List<WordHistoryEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.history;
    return widget.history
        .where((e) => (e.enrichedText ?? e.text).toLowerCase().contains(q))
        .toList();
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (!_favorites.remove(id)) _favorites.add(id);
    });
    widget.onToggleFavorite(id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final history = _filtered;
    final total = widget.history.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _query.isEmpty
                  ? '历史记录 ($total)'
                  : '历史记录 (${history.length}/$total)',
              style: TextStyle(
                fontFamily: AppFonts.displayZh,
                fontSize: 17,
                color: colors.foreground,
              ),
            ),
            if (total > 0)
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onClear();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.dangerSoft,
                    borderRadius: BorderRadius.circular(Radii.xs),
                  ),
                  child: Text(
                    '清空',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.dangerMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        if (total >= _searchThreshold) ...[
          DrawerSearchField(
            controller: _searchController,
            value: _query,
            onChanged: (v) => setState(() => _query = v),
            hintText: '搜索词表内容',
          ),
          const SizedBox(height: Spacing.sm),
        ],
        Flexible(
          child: history.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.surface),
                  ),
                  child: Text(
                    _query.isEmpty ? '尚无历史记录' : '没有匹配的历史记录',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.subtle),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  itemCount: history.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    return _HistoryRow(
                      entry: entry,
                      favorited: _favorites.contains(entry.id),
                      onApply: () {
                        widget.onApply(entry);
                        Navigator.of(context).pop();
                      },
                      onDelete: () {
                        Navigator.of(context).pop();
                        widget.onDelete(entry.id);
                      },
                      onToggleFavorite: () => _toggleFavorite(entry.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.favorited,
    required this.onApply,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final WordHistoryEntry entry;
  final bool favorited;
  final VoidCallback onApply;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preview = entry.text.replaceAll('\n', ' ');

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label:
                  '载入历史记录 ${preview.length > 20 ? preview.substring(0, 20) : preview}',
              child: GestureDetector(
                onTap: onApply,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: Spacing.sm + 2,
                    bottom: Spacing.sm + 2,
                    left: Spacing.sm + 2,
                    right: Spacing.sm,
                  ),
                  child: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.foreground,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              top: Spacing.sm + 2,
              bottom: Spacing.sm + 2,
              right: Spacing.sm + 2,
            ),
            child: Row(
              children: [
                Text(
                  '${_wordCount(entry.text)}',
                  style: TextStyle(fontSize: 11, color: colors.subtle),
                ),
                const SizedBox(width: Spacing.sm),
                Semantics(
                  button: true,
                  label: favorited ? '取消收藏' : '收藏',
                  child: GestureDetector(
                    onTap: onToggleFavorite,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      favorited ? AppIcons.star : AppIcons.starOutline,
                      size: 18,
                      color: favorited ? colors.gold : colors.subtle,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Semantics(
                  button: true,
                  label: '删除',
                  child: GestureDetector(
                    onTap: onDelete,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      AppIcons.closeCircle,
                      size: 20,
                      color: colors.subtle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
