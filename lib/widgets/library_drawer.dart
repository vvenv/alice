import 'package:flutter/material.dart';

import '../models/library_item.dart';
import '../models/word_history_entry.dart';
import '../services/dictation.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_bottom_sheet.dart';
import 'app_icons.dart';
import 'drawer_search_field.dart';

/// 词库抽屉：按分类折叠、可搜索、可收藏。
///
/// 对应 RN 版 src/components/LibraryDrawer.tsx。
Future<void> showLibraryDrawer(
  BuildContext context, {
  required List<LibraryGroup> groups,
  required List<String> favorites,
  required ValueChanged<WordHistoryEntry> onApply,
  required ValueChanged<String> onToggleFavorite,
}) {
  return showAppBottomSheet<void>(
    context: context,
    title: null, // 标题由内部维护（要跟着搜索结果变计数）
    builder: (sheetContext) => _LibraryDrawerBody(
      groups: groups,
      initialFavorites: favorites,
      onApply: onApply,
      onToggleFavorite: onToggleFavorite,
    ),
  );
}

int _wordCount(String text) => parseWords(text).length;

/// 小写化并去掉常见分隔符，让「七上unit1」能匹配「七上 Unit 1」。
String _normalizeForSearch(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s\-_./]+'), '');

bool _matchesTitle(String haystack, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (haystack.toLowerCase().contains(q)) return true;
  final normalizedQuery = _normalizeForSearch(q);
  if (normalizedQuery.isEmpty) return true;
  return _normalizeForSearch(haystack).contains(normalizedQuery);
}

List<LibraryGroup> _filterLibraryGroups(
  List<LibraryGroup> groups,
  String query,
) {
  final q = query.trim();
  if (q.isEmpty) return groups;

  return groups
      .map((group) {
        final categoryMatches = _matchesTitle(group.category, q);
        return LibraryGroup(
          category: group.category,
          items: categoryMatches
              ? group.items
              : group.items
                  .where((item) => _matchesTitle(item.label, q))
                  .toList(),
        );
      })
      .where((group) => group.items.isNotEmpty)
      .toList();
}

class _LibraryDrawerBody extends StatefulWidget {
  const _LibraryDrawerBody({
    required this.groups,
    required this.initialFavorites,
    required this.onApply,
    required this.onToggleFavorite,
  });

  final List<LibraryGroup> groups;
  final List<String> initialFavorites;
  final ValueChanged<WordHistoryEntry> onApply;
  final ValueChanged<String> onToggleFavorite;

  @override
  State<_LibraryDrawerBody> createState() => _LibraryDrawerBodyState();
}

class _LibraryDrawerBodyState extends State<_LibraryDrawerBody> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<String> _expandedCategories = <String>{};
  late final Set<String> _favorites = widget.initialFavorites.toSet();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isFiltering => _query.trim().isNotEmpty;

  bool _isGroupExpanded(String category) =>
      _isFiltering || _expandedCategories.contains(category);

  void _toggleGroup(String category) {
    setState(() {
      if (!_expandedCategories.remove(category)) {
        _expandedCategories.add(category);
      }
    });
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
    final filteredGroups = _filterLibraryGroups(widget.groups, _query);
    final totalCount = widget.groups.fold<int>(0, (n, g) => n + g.items.length);
    final filteredCount =
        filteredGroups.fold<int>(0, (n, g) => n + g.items.length);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Text(
            '词库 (${_isFiltering ? filteredCount : totalCount})',
            style: TextStyle(
              fontFamily: AppFonts.displayZh,
              fontSize: 17,
              color: colors.foreground,
            ),
          ),
        ),
        DrawerSearchField(
          controller: _searchController,
          value: _query,
          onChanged: (v) => setState(() => _query = v),
          hintText: '搜索标题或分类',
        ),
        const SizedBox(height: Spacing.sm),
        // 用 Flexible 吃掉标题/搜索之外的剩余高度，避免再手算
        // bodyMaxHeight - 搜索行 —— 漏算标题时列表会把抽屉底撑破。
        Flexible(
          child: _buildList(context, filteredGroups, totalCount, filteredCount),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    List<LibraryGroup> filteredGroups,
    int totalCount,
    int filteredCount,
  ) {
    final colors = context.colors;

    if (totalCount == 0 || filteredCount == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.surface),
        ),
        child: Text(
          totalCount == 0 ? '词库为空' : '未找到匹配词库',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colors.subtle),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      itemCount: filteredGroups.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.md),
      itemBuilder: (context, index) {
        final group = filteredGroups[index];
        final expanded = _isGroupExpanded(group.category);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: expanded,
              label: '${group.category}，${group.items.length} 个词表'
                  '${expanded ? '，已展开' : '，已折叠'}',
              child: GestureDetector(
                onTap: _isFiltering ? null : () => _toggleGroup(group.category),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.xs,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        expanded
                            ? AppIcons.chevronDown
                            : AppIcons.chevronForward,
                        size: 14,
                        color: colors.subtle,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          group.category,
                          style: TextStyle(
                            fontFamily: AppFonts.displayZh,
                            fontSize: 12,
                            color: colors.subtle,
                          ),
                        ),
                      ),
                      Text(
                        '${group.items.length}',
                        style: TextStyle(fontSize: 11, color: colors.subtle),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: Spacing.xs),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: colors.borderSubtle),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < group.items.length; i++)
                      _LibraryRow(
                        item: group.items[i],
                        favorited: _favorites.contains(group.items[i].entry.id),
                        showDivider: i > 0,
                        onApply: () {
                          widget.onApply(group.items[i].entry);
                          Navigator.of(context).pop();
                        },
                        onToggleFavorite: () =>
                            _toggleFavorite(group.items[i].entry.id),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.item,
    required this.favorited,
    required this.showDivider,
    required this.onApply,
    required this.onToggleFavorite,
  });

  final LibraryItem item;
  final bool favorited;
  final bool showDivider;
  final VoidCallback onApply;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: '载入 ${item.label}',
      child: GestureDetector(
        onTap: onApply,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: Spacing.sm + 2,
            horizontal: Spacing.sm + 2,
          ),
          decoration: showDivider
              ? BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.borderSubtle, width: 0.5),
                  ),
                )
              : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.foreground,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                '${_wordCount(item.entry.text)}',
                style: TextStyle(fontSize: 11, color: colors.subtle),
              ),
              const SizedBox(width: Spacing.sm),
              Semantics(
                button: true,
                label: favorited ? '取消收藏' : '收藏',
                child: GestureDetector(
                  onTap: onToggleFavorite,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      favorited ? AppIcons.star : AppIcons.starOutline,
                      size: 18,
                      color: favorited ? colors.gold : colors.subtle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
