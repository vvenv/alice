import 'package:flutter/material.dart';

import '../models/word_history_entry.dart';
import '../services/dictation.dart';
import '../services/library_data.dart';
import '../services/storage.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_bottom_sheet.dart';
import 'app_icons.dart';
import 'drawer_search_field.dart';

/// 收藏抽屉。对应 RN 版 src/components/FavoritesDrawer.tsx。
Future<void> showFavoritesDrawer(
  BuildContext context, {
  required List<String> favorites,
  required List<WordHistoryEntry> history,
  required ValueChanged<WordHistoryEntry> onApply,
  required ValueChanged<String> onToggleFavorite,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (sheetContext) => _FavoritesDrawerBody(
      initialFavorites: favorites,
      history: history,
      onApply: onApply,
      onToggleFavorite: onToggleFavorite,
    ),
  );
}

int _wordCount(String text) => parseWords(text).length;

enum _FavoriteSource { library, history }

class _FavoriteItem {
  const _FavoriteItem({
    required this.entry,
    required this.source,
    required this.label,
  });

  final WordHistoryEntry entry;
  final _FavoriteSource source;
  final String label;
}

/// 把收藏 id 解析成可展示的条目，跳过来源已被删除的孤儿 id。
List<_FavoriteItem> _resolveFavorites(
  List<String> favorites,
  List<WordHistoryEntry> history,
) {
  final result = <_FavoriteItem>[];
  for (final id in favorites) {
    if (isLibraryId(id)) {
      final libItem = getLibraryItemById(id);
      if (libItem != null) {
        result.add(_FavoriteItem(
          entry: libItem.entry,
          source: _FavoriteSource.library,
          label: '${libItem.category} · ${libItem.label}',
        ));
      }
    } else {
      for (final e in history) {
        if (e.id == id) {
          result.add(_FavoriteItem(
            entry: e,
            source: _FavoriteSource.history,
            label: e.text.replaceAll('\n', ' '),
          ));
          break;
        }
      }
    }
  }
  return result;
}

class _FavoritesDrawerBody extends StatefulWidget {
  const _FavoritesDrawerBody({
    required this.initialFavorites,
    required this.history,
    required this.onApply,
    required this.onToggleFavorite,
  });

  final List<String> initialFavorites;
  final List<WordHistoryEntry> history;
  final ValueChanged<WordHistoryEntry> onApply;
  final ValueChanged<String> onToggleFavorite;

  @override
  State<_FavoritesDrawerBody> createState() => _FavoritesDrawerBodyState();
}

/// 与历史抽屉同一个门槛：条目少时搜索框只是噪音。
const int _searchThreshold = 6;

class _FavoritesDrawerBodyState extends State<_FavoritesDrawerBody> {
  late List<String> _favorites = List<String>.from(widget.initialFavorites);
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _remove(String id) {
    setState(() => _favorites = _favorites.where((x) => x != id).toList());
    widget.onToggleFavorite(id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final all = _resolveFavorites(_favorites, widget.history);
    final q = _query.trim().toLowerCase();
    // 标题（词库分类 / 历史正文首行）已经是用户能记住的那一串。
    final items = q.isEmpty
        ? all
        : all.where((i) => i.label.toLowerCase().contains(q)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Text(
            _query.isEmpty
                ? '收藏 (${all.length})'
                : '收藏 (${items.length}/${all.length})',
            style: TextStyle(
              fontFamily: AppFonts.displayZh,
              fontSize: 17,
              color: colors.foreground,
            ),
          ),
        ),
        if (all.length >= _searchThreshold) ...[
          DrawerSearchField(
            controller: _searchController,
            value: _query,
            onChanged: (v) => setState(() => _query = v),
            hintText: '搜索收藏',
          ),
          const SizedBox(height: Spacing.sm),
        ],
        Flexible(
          child: items.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.surface),
                  ),
                  child: Text(
                    _query.isEmpty ? '尚无收藏' : '没有匹配的收藏',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.subtle),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _FavoriteRow(
                      item: item,
                      onApply: () {
                        widget.onApply(item.entry);
                        Navigator.of(context).pop();
                      },
                      onRemove: () => _remove(item.entry.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({
    required this.item,
    required this.onApply,
    required this.onRemove,
  });

  final _FavoriteItem item;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
              label: '载入收藏 ${item.label}',
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
                  '${_wordCount(item.entry.text)}',
                  style: TextStyle(fontSize: 11, color: colors.subtle),
                ),
                const SizedBox(width: Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.xs + 2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(Radii.xs),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Text(
                    item.source == _FavoriteSource.library ? '词库' : '历史',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: colors.subtle,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Semantics(
                  button: true,
                  label: '取消收藏',
                  child: GestureDetector(
                    onTap: onRemove,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(AppIcons.star, size: 18, color: colors.gold),
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
