import { Ionicons } from "@expo/vector-icons";
import {
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import { parseWords } from "../lib/dictation";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";
import type { WordHistoryEntry } from "../lib/storage";

interface HistoryDrawerProps {
  visible: boolean;
  history: WordHistoryEntry[];
  onClose: () => void;
  onApply: (text: string) => void;
  onDelete: (id: string) => void;
  onClear: () => void;
}

function isDefaultEntry(entry: WordHistoryEntry): boolean {
  return entry.id.startsWith("default_");
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
  const userEntries = history.filter((e) => !isDefaultEntry(e));

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onClose}
    >
      <View style={[styles.backdrop, { backgroundColor: colors.overlay }]}>
        <Pressable style={styles.backdropSpacer} onPress={onClose} />
        <View
          style={[
            styles.drawer,
            {
              backgroundColor: colors.background,
              borderColor: colors.borderSubtle,
            },
          ]}
        >
          <View style={[styles.handle, { backgroundColor: colors.border }]} />

          <View style={styles.header}>
            <Text style={[styles.title, { color: colors.foreground }]}>
              历史记录 ({history.length})
            </Text>
            <TouchableOpacity
              onPress={onClose}
              activeOpacity={0.6}
              hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            >
              <Ionicons name="close" size={22} color={colors.muted} />
            </TouchableOpacity>
          </View>

          {userEntries.length > 0 && (
            <TouchableOpacity
              style={[styles.clearBtn, { backgroundColor: colors.dangerSoft }]}
              onPress={onClear}
              activeOpacity={0.7}
            >
              <Text style={[styles.clearBtnText, { color: colors.dangerMuted }]}>
                清空自定义记录
              </Text>
            </TouchableOpacity>
          )}

          <ScrollView
            style={styles.list}
            contentContainerStyle={styles.listContent}
            showsVerticalScrollIndicator={false}
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
                      onApply(entry.text);
                      onClose();
                    }}
                    activeOpacity={0.6}
                  >
                    <Text
                      style={[styles.itemText, { color: colors.foreground }]}
                      numberOfLines={1}
                      ellipsizeMode="tail"
                    >
                      {isDefaultEntry(entry)
                        ? entry.id.replace("default_", "")
                        : entry.text.replace(/\n/g, " ")}
                    </Text>
                    <Text style={[styles.itemMeta, { color: colors.subtle }]}>
                      {wordCount(entry.text)}
                      {isDefaultEntry(entry) ? " · 内置" : null}
                    </Text>
                  </TouchableOpacity>
                  {!isDefaultEntry(entry) && (
                    <TouchableOpacity
                      style={styles.itemDelete}
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
                  )}
                </View>
              ))
            )}
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    justifyContent: "flex-end",
  },
  backdropSpacer: {
    flex: 1,
  },
  drawer: {
    maxHeight: "80%",
    borderTopLeftRadius: radii.shell,
    borderTopRightRadius: radii.shell,
    borderWidth: 1,
    borderBottomWidth: 0,
    padding: spacing.lg,
    paddingBottom: spacing.xl,
  },
  handle: {
    width: 36,
    height: 4,
    borderRadius: radii.full,
    alignSelf: "center",
    marginBottom: spacing.md,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: spacing.sm,
  },
  title: {
    fontSize: 17,
    fontWeight: "700",
  },
  clearBtn: {
    alignSelf: "flex-start",
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    borderRadius: radii.xs,
    marginBottom: spacing.md,
  },
  clearBtnText: {
    fontSize: 12,
    fontWeight: "500",
  },
  list: {
    flex: 1,
    minHeight: 0,
  },
  listContent: {
    gap: spacing.sm,
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
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: spacing.sm,
    padding: spacing.sm + 2,
  },
  itemText: {
    fontSize: 14,
    fontWeight: "500",
    marginBottom: 2,
  },
  itemMeta: {
    fontSize: 11,
  },
  itemDelete: {
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.sm + 2,
  },
});
