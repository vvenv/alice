import { Ionicons } from "@expo/vector-icons";
import { useEffect, useMemo, useState } from "react";
import {
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import { parseWords } from "../lib/dictation";
import { fonts, radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";
import type { LibraryGroup, WordHistoryEntry } from "../lib/storage";
import { BottomSheet } from "./BottomSheet";

interface LibraryDrawerProps {
  visible: boolean;
  groups: LibraryGroup[];
  onClose: () => void;
  onApply: (entry: WordHistoryEntry) => void;
}

/** Approximate height of the search row (input + gap) for ScrollView budgeting. */
const SEARCH_BLOCK_HEIGHT = 44;

function wordCount(text: string): number {
  return parseWords(text).length;
}

/** Lowercase and strip common separators so "七上unit1" matches "七上 Unit 1". */
function normalizeForSearch(value: string): string {
  return value.toLowerCase().replace(/[\s\-_./]+/g, "");
}

function matchesTitle(haystack: string, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  if (haystack.toLowerCase().includes(q)) return true;
  const normalizedQuery = normalizeForSearch(q);
  if (!normalizedQuery) return true;
  return normalizeForSearch(haystack).includes(normalizedQuery);
}

function filterLibraryGroups(
  groups: LibraryGroup[],
  query: string,
): LibraryGroup[] {
  const q = query.trim();
  if (!q) return groups;

  return groups
    .map((group) => {
      const categoryMatches = matchesTitle(group.category, q);
      return {
        category: group.category,
        items: categoryMatches
          ? group.items
          : group.items.filter((item) => matchesTitle(item.label, q)),
      };
    })
    .filter((group) => group.items.length > 0);
}

export function LibraryDrawer({
  visible,
  groups,
  onClose,
  onApply,
}: LibraryDrawerProps) {
  const colors = useThemeColors();
  const [query, setQuery] = useState("");
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(
    () => new Set(),
  );

  useEffect(() => {
    if (!visible) {
      setQuery("");
      setExpandedCategories(new Set());
    }
  }, [visible]);

  const filteredGroups = useMemo(
    () => filterLibraryGroups(groups, query),
    [groups, query],
  );
  const totalCount = groups.reduce((n, g) => n + g.items.length, 0);
  const filteredCount = filteredGroups.reduce((n, g) => n + g.items.length, 0);
  const isFiltering = query.trim().length > 0;

  const isGroupExpanded = (category: string) =>
    isFiltering || expandedCategories.has(category);

  const toggleGroup = (category: string) => {
    setExpandedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(category)) next.delete(category);
      else next.add(category);
      return next;
    });
  };

  return (
    <BottomSheet
      visible={visible}
      onClose={onClose}
      title={`词库 (${isFiltering ? filteredCount : totalCount})`}
    >
      {(bodyMaxHeight) => (
        <View style={[styles.body, { maxHeight: bodyMaxHeight }]}>
          <View
            style={[
              styles.searchRow,
              {
                backgroundColor: colors.surfaceSunken,
                borderColor: colors.border,
              },
            ]}
          >
            <Ionicons
              name="search-outline"
              size={16}
              color={colors.subtle}
              style={styles.searchIcon}
            />
            <TextInput
              style={[styles.searchInput, { color: colors.foreground }]}
              value={query}
              onChangeText={setQuery}
              placeholder="搜索标题或分类"
              placeholderTextColor={colors.subtle}
              returnKeyType="search"
              autoCorrect={false}
              autoCapitalize="none"
              clearButtonMode="never"
              accessibilityLabel="搜索词库标题"
            />
            {query.length > 0 ? (
              <TouchableOpacity
                onPress={() => setQuery("")}
                hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
                accessibilityRole="button"
                accessibilityLabel="清除搜索"
              >
                <Ionicons name="close-circle" size={16} color={colors.subtle} />
              </TouchableOpacity>
            ) : null}
          </View>

          <ScrollView
            style={{
              maxHeight: Math.max(80, bodyMaxHeight - SEARCH_BLOCK_HEIGHT),
            }}
            contentContainerStyle={styles.listContent}
            showsVerticalScrollIndicator={false}
            bounces={false}
            nestedScrollEnabled
            keyboardShouldPersistTaps="handled"
          >
            {totalCount === 0 ? (
              <Text
                style={[
                  styles.empty,
                  { color: colors.subtle, backgroundColor: colors.surface },
                ]}
              >
                词库为空
              </Text>
            ) : filteredCount === 0 ? (
              <Text
                style={[
                  styles.empty,
                  { color: colors.subtle, backgroundColor: colors.surface },
                ]}
              >
                未找到匹配词库
              </Text>
            ) : (
              filteredGroups.map((group) => {
                const expanded = isGroupExpanded(group.category);
                return (
                  <View key={group.category} style={styles.section}>
                    <TouchableOpacity
                      style={styles.sectionHeader}
                      onPress={() => {
                        if (!isFiltering) toggleGroup(group.category);
                      }}
                      activeOpacity={isFiltering ? 1 : 0.6}
                      disabled={isFiltering}
                      accessibilityRole="button"
                      accessibilityState={{ expanded }}
                      accessibilityLabel={`${group.category}，${group.items.length} 个词表${expanded ? "，已展开" : "，已折叠"}`}
                    >
                      <Ionicons
                        name={expanded ? "chevron-down" : "chevron-forward"}
                        size={14}
                        color={colors.subtle}
                      />
                      <Text
                        style={[styles.sectionTitle, { color: colors.subtle }]}
                      >
                        {group.category}
                      </Text>
                      <Text
                        style={[styles.sectionCount, { color: colors.subtle }]}
                      >
                        {group.items.length}
                      </Text>
                    </TouchableOpacity>
                    {expanded ? (
                      <View
                        style={[
                          styles.sectionBody,
                          {
                            backgroundColor: colors.surface,
                            borderColor: colors.borderSubtle,
                          },
                        ]}
                      >
                        {group.items.map((item, idx) => (
                          <TouchableOpacity
                            key={item.entry.id}
                            style={[
                              styles.item,
                              idx > 0 && {
                                borderTopColor: colors.borderSubtle,
                                borderTopWidth: StyleSheet.hairlineWidth,
                              },
                            ]}
                            onPress={() => {
                              onApply(item.entry);
                              onClose();
                            }}
                            activeOpacity={0.6}
                            accessibilityRole="button"
                            accessibilityLabel={`载入 ${item.label}`}
                          >
                            <Text
                              style={[
                                styles.itemText,
                                { color: colors.foreground },
                              ]}
                              numberOfLines={1}
                              ellipsizeMode="tail"
                            >
                              {item.label}
                            </Text>
                            <Text
                              style={[
                                styles.itemMeta,
                                { color: colors.subtle },
                              ]}
                            >
                              {wordCount(item.entry.text)}
                            </Text>
                          </TouchableOpacity>
                        ))}
                      </View>
                    ) : null}
                  </View>
                );
              })
            )}
          </ScrollView>
        </View>
      )}
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  body: {
    gap: spacing.sm,
  },
  searchRow: {
    flexDirection: "row",
    alignItems: "center",
    borderWidth: 1,
    borderRadius: radii.control,
    paddingHorizontal: spacing.sm + 2,
    minHeight: 36,
  },
  searchIcon: {
    marginRight: spacing.xs,
  },
  searchInput: {
    flex: 1,
    fontSize: 14,
    paddingVertical: spacing.sm,
  },
  listContent: {
    gap: spacing.md,
    paddingBottom: spacing.sm,
  },
  empty: {
    textAlign: "center",
    fontSize: 13,
    paddingVertical: spacing.lg,
    borderRadius: radii.surface,
  },
  section: {
    gap: spacing.xs,
  },
  sectionHeader: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.xs,
    paddingHorizontal: spacing.xs,
    paddingVertical: 2,
  },
  sectionTitle: {
    flex: 1,
    fontFamily: fonts.displayZh,
    fontSize: 12,
    fontWeight: "600",
    textTransform: "uppercase",
  },
  sectionCount: {
    fontSize: 11,
  },
  sectionBody: {
    borderRadius: radii.control,
    borderWidth: 1,
    overflow: "hidden",
  },
  item: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingVertical: spacing.sm + 2,
    paddingLeft: spacing.sm + 2,
    paddingRight: spacing.sm + 2,
  },
  itemText: {
    flex: 1,
    fontSize: 14,
    fontWeight: "500",
  },
  itemMeta: {
    fontSize: 11,
    marginLeft: spacing.sm,
  },
});
