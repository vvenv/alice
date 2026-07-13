import { Ionicons } from "@expo/vector-icons";
import { useEffect, useRef } from "react";
import {
  Animated,
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
    bottomPad;
  const listMaxHeight = Math.max(160, drawerMaxHeight - chromeHeight);

  // Modal slide animates the whole tree (backdrop included). Keep Modal static
  // and slide only the drawer panel.
  const drawerTranslateY = useRef(new Animated.Value(drawerMaxHeight)).current;

  useEffect(() => {
    if (!visible) {
      drawerTranslateY.setValue(drawerMaxHeight);
      return;
    }
    drawerTranslateY.setValue(drawerMaxHeight);
    Animated.timing(drawerTranslateY, {
      toValue: 0,
      duration: 280,
      useNativeDriver: true,
    }).start();
  }, [visible, drawerMaxHeight, drawerTranslateY]);

  return (
    <Modal
      visible={visible}
      transparent
      animationType="none"
      onRequestClose={onClose}
      statusBarTranslucent={Platform.OS === "android"}
      presentationStyle="overFullScreen"
    >
      <View style={styles.root}>
        <Pressable
          style={[styles.backdrop, { backgroundColor: colors.overlay }]}
          onPress={onClose}
        />
        <Animated.View
          style={[
            styles.drawer,
            {
              backgroundColor: colors.background,
              borderColor: colors.borderSubtle,
              maxHeight: drawerMaxHeight,
              paddingBottom: bottomPad,
              transform: [{ translateY: drawerTranslateY }],
            },
          ]}
        >
          <View style={[styles.handle, { backgroundColor: colors.border }]} />

          <View style={styles.header}>
            <Text style={[styles.title, { color: colors.foreground }]}>
              历史记录 ({history.length})
            </Text>
            {userEntries.length > 0 && (
              <TouchableOpacity
                style={[styles.clearBtn, { backgroundColor: colors.dangerSoft }]}
                onPress={onClear}
                activeOpacity={0.7}
              >
                <Text style={[styles.clearBtnText, { color: colors.dangerMuted }]}>
                  清空
                </Text>
              </TouchableOpacity>
            )}
          </View>

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
                  </TouchableOpacity>
                  <View style={styles.itemTrailing}>
                    <Text style={[styles.itemMeta, { color: colors.subtle }]}>
                      {wordCount(entry.text)}
                      {isDefaultEntry(entry) ? " · 内置" : null}
                    </Text>
                    {!isDefaultEntry(entry) && (
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
                    )}
                  </View>
                </View>
              ))
            )}
          </ScrollView>
        </Animated.View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    justifyContent: "flex-end",
  },
  backdrop: {
    ...StyleSheet.absoluteFill,
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
