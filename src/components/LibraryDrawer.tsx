import {
  ScrollView,
  StyleSheet,
  Text,
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

function wordCount(text: string): number {
  return parseWords(text).length;
}

export function LibraryDrawer({
  visible,
  groups,
  onClose,
  onApply,
}: LibraryDrawerProps) {
  const colors = useThemeColors();
  const totalCount = groups.reduce((n, g) => n + g.items.length, 0);

  return (
    <BottomSheet
      visible={visible}
      onClose={onClose}
      title={`词库 (${totalCount})`}
    >
      {(bodyMaxHeight) => (
        <ScrollView
          style={{ maxHeight: bodyMaxHeight }}
          contentContainerStyle={styles.listContent}
          showsVerticalScrollIndicator={false}
          bounces={false}
          nestedScrollEnabled
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
          ) : (
            groups.map((group) => (
              <View key={group.category} style={styles.section}>
                <Text style={[styles.sectionTitle, { color: colors.subtle }]}>
                  {group.category}
                </Text>
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
                        style={[styles.itemText, { color: colors.foreground }]}
                        numberOfLines={1}
                        ellipsizeMode="tail"
                      >
                        {item.label}
                      </Text>
                      <Text style={[styles.itemMeta, { color: colors.subtle }]}>
                        {wordCount(item.entry.text)}
                      </Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>
            ))
          )}
        </ScrollView>
      )}
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
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
  sectionTitle: {
    fontFamily: fonts.display,
    fontSize: 12,
    fontWeight: "600",
    paddingHorizontal: spacing.xs,
    textTransform: "uppercase",
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
