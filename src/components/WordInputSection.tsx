import { useMemo } from "react";
import {
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import { parseWords, parseWordLine } from "../lib/dictation";
import { fonts, radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";
import { Button } from "./Button";

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
              borderColor: colors.borderSubtle,
              backgroundColor: colors.surfaceRaised,
            },
          ]}
        >
          <ScrollView
            style={styles.displayScroll}
            showsVerticalScrollIndicator={false}
            nestedScrollEnabled
          >
            {parsedWords.map((line, idx) => {
              const isCursor = idx === startIndex;
              const entry = parseWordLine(line);
              const hasMeta = Boolean(entry.pos || entry.meaning);
              return (
                <TouchableOpacity
                  key={`display-${line}-${idx}`}
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
                  <View style={styles.displayWordCol}>
                    <Text
                      style={[
                        styles.displayWord,
                        { color: isCursor ? colors.primary : colors.foreground },
                      ]}
                    >
                      {entry.word}
                    </Text>
                    {hasMeta && (
                      <Text
                        style={[
                          styles.displayMeta,
                          { color: colors.subtle },
                        ]}
                      >
                        {entry.pos ? `${entry.pos} ` : ""}
                        {entry.meaning ?? ""}
                      </Text>
                    )}
                  </View>
                  {isCursor && (
                    <View
                      style={[styles.cursorBar, { backgroundColor: colors.primary }]}
                    />
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
          placeholder="每行一个单词或词组\n例：apple\nactor / actress"
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
            <Button label="示例" variant="outline" size="sm" onPress={onSetSample} />
            <Button label="清空" variant="outline" size="sm" onPress={onClear} />
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
  displayContainer: {
    flex: 1,
    minHeight: 0,
    borderWidth: 1,
    borderRadius: radii.card,
    overflow: "hidden",
    shadowColor: "#000",
    shadowOpacity: 0.08,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 6 },
    elevation: 3,
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
    paddingVertical: spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderLeftWidth: 3,
    borderLeftColor: "transparent",
    gap: spacing.md,
  },
  displayIndex: {
    fontFamily: fonts.serif,
    fontSize: 13,
    fontWeight: "600",
    fontVariant: ["tabular-nums"],
    minWidth: 24,
  },
  displayWord: {
    fontSize: 16,
    fontWeight: "500",
  },
  displayWordCol: {
    flex: 1,
    flexDirection: "column",
    gap: 2,
  },
  displayMeta: {
    fontSize: 12,
    lineHeight: 16,
  },
  cursorBar: {
    width: 3,
    height: 20,
    borderRadius: 2,
  },
});
