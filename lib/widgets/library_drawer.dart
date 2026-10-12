import 'dart:async';

import 'package:flutter/material.dart';

import '../models/library_item.dart';
import '../models/word_history_entry.dart';
import '../services/dictation.dart';
import '../services/storage.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_bottom_sheet.dart';
import 'app_icons.dart';
import 'drawer_search_field.dart';

/// 词库抽屉：按分类折叠、可搜索、可收藏。打开时停在上次用的那个分类上。
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

/// 一个分类里共用同一段前缀的词表，如「七上」下的 Unit 1 ~ 8。
class _Section {
  _Section(this.title);

  /// 前缀（「七上」）；分类不分册时为 null。
  final String? title;
  final List<({LibraryItem item, String label})> cells = [];
}

/// 把一个分类的词表按册拆开。
///
/// 教材类的标签都是「七上 Unit 1」这种「册 + 单元」，一个分类六十来条，
/// 每条都把册名重复一遍。拆出来之后格子里只剩「Unit 1」，一行能排四个。
/// 字母表那种（A / B / … / XYZ）没有册，原样铺成一段。
List<_Section> _sectionsOf(List<LibraryItem> items) {
  final split = items.every((item) => item.label.contains(' '));
  if (!split) {
    final flat = _Section(null);
    for (final item in items) {
      flat.cells.add((item: item, label: item.label));
    }
    return [flat];
  }

  final sections = <_Section>[];
  for (final item in items) {
    final cut = item.label.indexOf(' ');
    final title = item.label.substring(0, cut);
    if (sections.isEmpty || sections.last.title != title) {
      sections.add(_Section(title));
    }
    sections.last.cells
        .add((item: item, label: item.label.substring(cut + 1).trim()));
  }
  return sections;
}

const double _cellGap = Spacing.sm;
const double _cellPadX = Spacing.sm;

/// 格子的最小宽度，按这个分类里最长的标签估。
///
/// 上限卡在 104：「Starter Unit 1」这种个别长标签靠缩字放进去，
/// 不为它把整个分类从三列拖成两列。
double _minCellWidth(List<_Section> sections) {
  var units = 0;
  for (final section in sections) {
    for (final cell in section.cells) {
      // 汉字按两个字符宽算。
      final n =
          cell.label.runes.fold<int>(0, (n, r) => n + (r > 0x2e80 ? 2 : 1));
      if (n > units) units = n;
    }
  }
  return (units * 7.5 + _cellPadX * 2 + 4).clamp(72.0, 104.0);
}

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
  // 上次停在哪个分类就先展开哪个 —— 一本教材要听一学期，每次进来都从
  // 全折叠开始找，是同一段路走几十遍。
  late final Set<String> _expandedCategories = <String>{
    if (loadLibraryCategory() case final category?) category,
  };
  late String? _lastItemId = loadLibraryItemId();
  late final Set<String> _favorites = widget.initialFavorites.toSet();
  final GlobalKey _currentCellKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 上次那条可能在「六下」，离展开的分类开头好几屏 —— 直接滚到它跟前，
    // 下一个单元就在旁边。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cell = _currentCellKey.currentContext;
      if (cell != null) Scrollable.ensureVisible(cell, alignment: 0.3);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isFiltering => _query.trim().isNotEmpty;

  bool _isGroupExpanded(String category) =>
      _isFiltering || _expandedCategories.contains(category);

  void _toggleGroup(String category) {
    final opened = !_expandedCategories.contains(category);
    setState(() {
      if (opened) {
        _expandedCategories.add(category);
      } else {
        _expandedCategories.remove(category);
      }
    });
    // 记最后展开的那个；把它收起来就是不想再看到它。
    if (opened) {
      unawaited(saveLibraryCategory(category));
    } else if (loadLibraryCategory() == category) {
      unawaited(saveLibraryCategory(null));
    }
  }

  void _apply(LibraryItem item) {
    // 搜索结果里直接点的也算：下次打开就停在它所在的分类。
    unawaited(saveLibraryCategory(item.category));
    unawaited(saveLibraryItemId(item.entry.id));
    _lastItemId = item.entry.id;
    widget.onApply(item.entry);
    Navigator.of(context).pop();
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
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.lg),
      itemBuilder: (context, index) {
        final group = filteredGroups[index];
        final expanded = _isGroupExpanded(group.category);

        // 展开时整块成一张卡：分类头抬起，词表沉进井底，格子再浮上来。
        return Container(
          decoration: expanded
              ? BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(Radii.surface),
                  border: Border.all(color: colors.borderSubtle),
                )
              : null,
          clipBehavior: expanded ? Clip.antiAlias : Clip.none,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: expanded,
                label: '${group.category}，${group.items.length} 个词表'
                    '${expanded ? '，已展开' : '，已折叠'}',
                child: GestureDetector(
                  onTap:
                      _isFiltering ? null : () => _toggleGroup(group.category),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: expanded ? Spacing.md : Spacing.xs,
                      vertical: Spacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          expanded
                              ? AppIcons.chevronDown
                              : AppIcons.chevronForward,
                          size: 16,
                          color: expanded ? colors.muted : colors.subtle,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            group.category,
                            style: TextStyle(
                              fontFamily: AppFonts.displayZh,
                              fontSize: 15,
                              color: expanded
                                  ? colors.foreground
                                  : colors.muted,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: expanded
                                ? colors.surfaceSunken
                                : colors.surface,
                            borderRadius: BorderRadius.circular(Radii.full),
                          ),
                          child: Text(
                            '${group.items.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.subtle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (expanded)
                Container(
                  margin: const EdgeInsets.fromLTRB(
                    Spacing.sm,
                    0,
                    Spacing.sm,
                    Spacing.sm,
                  ),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.sm,
                    Spacing.sm,
                    Spacing.sm,
                    Spacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: _buildGrid(context, group),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 展开后的词表。格子而不是一行一条：标签只有「Unit 1」「A」这么短，
  /// 一行一条的话右边大半行都是空的，六十条要滚好几屏。
  Widget _buildGrid(BuildContext context, LibraryGroup group) {
    final colors = context.colors;
    final sections = _sectionsOf(group.items);
    final minWidth = _minCellWidth(sections);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns =
            ((width + _cellGap) / (minWidth + _cellGap)).floor().clamp(2, 8);
        // 往下取整，免得浮点误差把一行的最后一格挤到下一行。
        final cellWidth =
            ((width - _cellGap * (columns - 1)) / columns).floorToDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, section) in sections.indexed) ...[
              if (i > 0) const SizedBox(height: Spacing.md),
              if (section.title != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: Spacing.xs,
                    bottom: Spacing.sm,
                  ),
                  child: Text(
                    section.title!,
                    style: TextStyle(
                      fontFamily: AppFonts.serif,
                      fontSize: 12,
                      color: colors.subtle,
                    ),
                  ),
                ),
              Wrap(
                spacing: _cellGap,
                runSpacing: _cellGap,
                children: [
                  for (final cell in section.cells)
                    SizedBox(
                      width: cellWidth,
                      child: _LibraryCell(
                        key: cell.item.entry.id == _lastItemId
                            ? _currentCellKey
                            : null,
                        item: cell.item,
                        label: cell.label,
                        favorited: _favorites.contains(cell.item.entry.id),
                        current: cell.item.entry.id == _lastItemId,
                        onApply: () => _apply(cell.item),
                        onToggleFavorite: () =>
                            _toggleFavorite(cell.item.entry.id),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LibraryCell extends StatelessWidget {
  const _LibraryCell({
    super.key,
    required this.item,
    required this.label,
    required this.favorited,
    required this.current,
    required this.onApply,
    required this.onToggleFavorite,
  });

  final LibraryItem item;

  /// 格子里显示的短标签（去掉了册名）。读屏仍然报完整的 [LibraryItem.label]。
  final String label;
  final bool favorited;

  /// 上次载入的就是这一条 —— 描个边，方便接着往下听下一个单元。
  final bool current;
  final VoidCallback onApply;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final words = _wordCount(item.entry.text);

    return Semantics(
      button: true,
      selected: current,
      label: '载入 ${item.label}',
      value: '$words 词',
      child: GestureDetector(
        onTap: onApply,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.only(
            left: _cellPadX,
            top: Spacing.sm,
            bottom: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: current ? colors.primarySoft : colors.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: current ? colors.primary : colors.borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: _cellPadX),
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: current ? colors.primary : colors.foreground,
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    // 词数已经在外层的 value 里报过了。
                    child: ExcludeSemantics(
                      child: Text(
                        '$words 词',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(fontSize: 11, color: colors.subtle),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: favorited ? '取消收藏' : '收藏',
                    child: GestureDetector(
                      onTap: onToggleFavorite,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _cellPadX,
                          vertical: Spacing.xs,
                        ),
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
            ],
          ),
        ),
      ),
    );
  }
}
