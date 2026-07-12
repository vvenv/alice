import { Ionicons } from "@expo/vector-icons";
import {
  Dimensions,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
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
  const insets = useSafeAreaInsets();
  const userEntries = history.filter((e) => !isDefaultEntry(e));
  // Percentage maxHeight + flex:1 ScrollView is unreliable on Android Modal.
  const drawerMaxHeight = Dimensions.get("window").height * 0.8;
  const bottomPad = Math.max(insets.bottom, spacing.xl);
  const chromeHeight =
    spacing.lg + // paddingTop
    4 +
    spacing.md + // handle
    28 +
    spacing.sm + // header
    (userEntries.length > 0 ? 28 + spacing.md : 0) + // clear button
    bottomPad;
  const listMaxHeight = Math.max(160, drawerMaxHeight - chromeHeight);

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onClose}
      statusBarTranslucent={Platform.OS === "android"}
    >
      <View style={[styles.backdrop, { backgroundColor: colors.overlay }]}>
        <Pressable style={styles.backdropSpacer} onPress={onClose} />
        <View
          style={[
            styles.drawer,
            {
              backgroundColor: colors.background,
              borderColor: colors.borderSubtle,
              maxHeight: drawerMaxHeight,
              paddingBottom: bottomPad,
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
            style={{ maxHeight: listMaxHeight }}
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
    borderTopLeftRadius: radii.shell,
    borderTopRightRadius: radii.shell,
    borderWidth: 1,
    borderBottomWidth: 0,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
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
