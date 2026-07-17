import { Ionicons } from "@expo/vector-icons";
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";

import type { WordHistoryEntry } from "../lib/storage";
import { parseWords } from "../lib/dictation";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";
import { BottomSheet } from "./BottomSheet";

interface HistoryDrawerProps {
  visible: boolean;
  history: WordHistoryEntry[];
  onClose: () => void;
  onApply: (entry: WordHistoryEntry) => void;
  onDelete: (id: string) => void;
  onClear: () => void;
}

function wordCount(text: string): number {
  return parseWords(text).length;
}

export function HistoryDrawer({
  visible,
  history,
  onClose,
  onApply,
  onDelete,
  onClear,
}: HistoryDrawerProps) {
  const colors = useThemeColors();

  return (
    <BottomSheet
      visible={visible}
      onClose={onClose}
      title={`历史记录 (${history.length})`}
      headerRight={
        history.length > 0 ? (
          <TouchableOpacity
            style={[styles.clearBtn, { backgroundColor: colors.dangerSoft }]}
            onPress={onClear}
            activeOpacity={0.7}
            hitSlop={{ top: 6, bottom: 6, left: 6, right: 6 }}
          >
            <Text style={[styles.clearBtnText, { color: colors.dangerMuted }]}>
              清空
            </Text>
          </TouchableOpacity>
        ) : undefined
      }
    >
      {(bodyMaxHeight) => (
        <ScrollView
          style={{ maxHeight: bodyMaxHeight }}
          contentContainerStyle={styles.listContent}
          showsVerticalScrollIndicator={false}
          bounces={false}
          nestedScrollEnabled
        >
          {history.length === 0 ? (
            <Text
              style={[
                styles.empty,
                { color: colors.subtle, backgroundColor: colors.surface },
              ]}
            >
              尚无历史记录
            </Text>
          ) : (
            history.map((entry) => (
              <View
                key={entry.id}
                style={[
                  styles.item,
                  {
                    backgroundColor: colors.surface,
                    borderColor: colors.borderSubtle,
                  },
                ]}
              >
                <TouchableOpacity
                  style={styles.itemContent}
                  onPress={() => {
                    onApply(entry);
                    onClose();
                  }}
                  activeOpacity={0.6}
                  accessibilityRole="button"
                  accessibilityLabel={`载入历史记录 ${entry.text.slice(0, 20)}`}
                >
                  <Text
                    style={[styles.itemText, { color: colors.foreground }]}
                    numberOfLines={1}
                    ellipsizeMode="tail"
                  >
                    {entry.text.replace(/\n/g, " ")}
                  </Text>
                </TouchableOpacity>
                <View style={styles.itemTrailing}>
                  <Text style={[styles.itemMeta, { color: colors.subtle }]}>
                    {wordCount(entry.text)}
                  </Text>
                  <TouchableOpacity
                    onPress={() => onDelete(entry.id)}
                    activeOpacity={0.6}
                    hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
                  >
                    <Ionicons
                      name="close-circle"
                      size={20}
                      color={colors.subtle}
                    />
                  </TouchableOpacity>
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
  clearBtn: {
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    borderRadius: radii.xs,
  },
  clearBtnText: {
    fontSize: 12,
    fontWeight: "500",
  },
  listContent: {
    gap: spacing.sm,
    paddingBottom: spacing.sm,
  },
  empty: {
    textAlign: "center",
    fontSize: 13,
    paddingVertical: spacing.lg,
    borderRadius: radii.surface,
  },
  item: {
    flexDirection: "row",
    alignItems: "center",
    borderRadius: radii.control,
    borderWidth: 1,
    overflow: "hidden",
  },
  itemContent: {
    flex: 1,
    paddingVertical: spacing.sm + 2,
    paddingLeft: spacing.sm + 2,
    paddingRight: spacing.sm,
  },
  itemText: {
    fontSize: 14,
    fontWeight: "500",
  },
  itemTrailing: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    paddingVertical: spacing.sm + 2,
    paddingRight: spacing.sm + 2,
  },
  itemMeta: {
    fontSize: 11,
  },
});
