import { useMemo } from "react";
import {
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import { parseWords } from "../lib/dictation";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

interface WordInputSectionProps {
  value: string;
  onChange: (value: string) => void;
  onSetSample: () => void;
  onClear: () => void;
  startIndex: number;
  onStartIndexChange: (index: number) => void;
  isDisplayMode: boolean;
}

export function WordInputSection({
  value,
  onChange,
  onSetSample,
  onClear,
  startIndex,
  onStartIndexChange,
  isDisplayMode,
}: WordInputSectionProps) {
  const colors = useThemeColors();
  const parsedWords = useMemo(() => parseWords(value), [value]);
  const wordCount = parsedWords.length;
  const effectiveDisplayMode = isDisplayMode && wordCount > 0;

  return (
    <View style={styles.container}>
      {effectiveDisplayMode ? (
        <View
          style={[
            styles.displayContainer,
            {
              borderColor: colors.border,
              backgroundColor: colors.surfaceSunken,
            },
          ]}
        >
          <ScrollView
            style={styles.displayScroll}
            showsVerticalScrollIndicator={false}
            nestedScrollEnabled
          >
            {parsedWords.map((word, idx) => {
              const isCursor = idx === startIndex;
              return (
                <TouchableOpacity
                  key={`display-${word}-${idx}`}
                  style={[
                    styles.displayRow,
                    isCursor && {
                      backgroundColor: colors.primarySoft,
                      borderLeftColor: colors.primary,
                    },
                    { borderBottomColor: colors.borderMuted },
                  ]}
                  onPress={() => onStartIndexChange(idx)}
                  activeOpacity={0.6}
                >
                  <Text
                    style={[
                      styles.displayIndex,
                      { color: isCursor ? colors.primary : colors.subtle },
                    ]}
                  >
                    {String(idx + 1).padStart(2, "0")}
                  </Text>
                  <Text
                    style={[
                      styles.displayWord,
                      { color: isCursor ? colors.primary : colors.foreground },
                    ]}
                  >
                    {word}
                  </Text>
                  {isCursor && (
                    <Text
                      style={[
                        styles.cursorIndicator,
                        { color: colors.primary },
                      ]}
                    >
                      ◀
                    </Text>
                  )}
                </TouchableOpacity>
              );
            })}
          </ScrollView>
        </View>
      ) : (
        <TextInput
          style={[
            styles.textArea,
            {
              borderColor: colors.border,
              backgroundColor: colors.surfaceSunken,
              color: colors.foreground,
            },
          ]}
          multiline
          placeholder="每行一个，或用逗号/空格分隔\n例：apple banana cat"
          placeholderTextColor={colors.subtle}
          value={value}
          onChangeText={onChange}
          editable
          textAlignVertical="top"
        />
      )}

      {!effectiveDisplayMode && (
        <View style={styles.footer}>
          <Text style={[styles.count, { color: colors.muted }]}>
            共 {wordCount} 个单词
          </Text>
          <View style={styles.actions}>
            <TouchableOpacity
              style={[styles.smallBtn, { borderColor: colors.border }]}
              onPress={onSetSample}
              activeOpacity={0.6}
            >
              <Text style={[styles.smallBtnText, { color: colors.secondary }]}>
                示例
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.smallBtn, { borderColor: colors.border }]}
              onPress={onClear}
              activeOpacity={0.6}
            >
              <Text style={[styles.smallBtnText, { color: colors.secondary }]}>
                清空
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    minHeight: 0,
    gap: spacing.xs,
  },
  textArea: {
    flex: 1,
    minHeight: 0,
    borderWidth: 1,
    borderRadius: radii.card,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    fontSize: 16,
    lineHeight: 22,
  },
  footer: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  count: {
    fontSize: 12,
  },
  actions: {
    flexDirection: "row",
    gap: 8,
  },
  smallBtn: {
    borderRadius: radii.full,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 4,
  },
  smallBtnText: {
    fontSize: 12,
    fontWeight: "500",
  },
  displayContainer: {
    flex: 1,
    minHeight: 0,
    borderWidth: 1,
    borderRadius: radii.card,
    overflow: "hidden",
  },
  displayScroll: {
    flex: 1,
    minHeight: 0,
    paddingVertical: spacing.sm,
  },
  displayRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm + 2,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderLeftWidth: 3,
    borderLeftColor: "transparent",
    gap: spacing.md,
  },
  displayIndex: {
    fontSize: 12,
    fontWeight: "600",
    fontVariant: ["tabular-nums"],
    minWidth: 24,
  },
  displayWord: {
    fontSize: 16,
    fontWeight: "500",
    flex: 1,
  },
  cursorIndicator: {
    fontSize: 14,
    fontWeight: "700",
  },
});
