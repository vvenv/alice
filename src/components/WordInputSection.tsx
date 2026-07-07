import { useCallback, useEffect, useMemo, useState } from "react";
import {
  type NativeSyntheticEvent,
  StyleSheet,
  Text,
  TextInput,
  type TextInputContentSizeChangeEventData,
  TouchableOpacity,
  View,
} from "react-native";

import { parseWords } from "../lib/dictation";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

const TEXT_AREA_MIN_HEIGHT = 88;
const TEXT_AREA_PADDING_V = spacing.md * 2;

interface WordInputSectionProps {
  value: string;
  onChange: (value: string) => void;
  onSetSample: () => void;
  onClear: () => void;
}

export function WordInputSection({
  value,
  onChange,
  onSetSample,
  onClear,
}: WordInputSectionProps) {
  const colors = useThemeColors();
  const wordCount = useMemo(() => parseWords(value).length, [value]);
  const [textAreaHeight, setTextAreaHeight] = useState(TEXT_AREA_MIN_HEIGHT);

  const handleContentSizeChange = useCallback(
    (event: NativeSyntheticEvent<TextInputContentSizeChangeEventData>) => {
      const next = Math.max(
        TEXT_AREA_MIN_HEIGHT,
        Math.ceil(event.nativeEvent.contentSize.height) + TEXT_AREA_PADDING_V,
      );
      setTextAreaHeight((prev) => (prev === next ? prev : next));
    },
    [],
  );

  useEffect(() => {
    if (!value) {
      setTextAreaHeight(TEXT_AREA_MIN_HEIGHT);
    }
  }, [value]);

  return (
    <View style={styles.container}>
      <TextInput
        style={[
          styles.textArea,
          { height: textAreaHeight },
          {
            borderColor: colors.border,
            backgroundColor: colors.surfaceSunken,
            color: colors.foreground,
          },
        ]}
        multiline
        scrollEnabled={false}
        placeholder="每行一个，或用逗号/空格分隔\n例：apple banana cat"
        placeholderTextColor={colors.subtle}
        value={value}
        onChangeText={onChange}
        onContentSizeChange={handleContentSizeChange}
        editable
        textAlignVertical="top"
      />
      <View style={styles.footer}>
        <Text style={[styles.count, { color: colors.muted }]}>共 {wordCount} 个单词</Text>
        <View style={styles.actions}>
          <TouchableOpacity
            style={[styles.smallBtn, { borderColor: colors.border }]}
            onPress={onSetSample}
            activeOpacity={0.6}
          >
            <Text style={[styles.smallBtnText, { color: colors.secondary }]}>示例</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.smallBtn, { borderColor: colors.border }]}
            onPress={onClear}
            activeOpacity={0.6}
          >
            <Text style={[styles.smallBtnText, { color: colors.secondary }]}>清空</Text>
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: spacing.sm,
  },
  textArea: {
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
});
