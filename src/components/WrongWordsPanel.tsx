import { StyleSheet, Text, TouchableOpacity, View } from "react-native";

import { radii } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

interface WrongWordsPanelProps {
  wrongWords: string[];
  onExport: () => void;
  onClear: () => void;
  onRemove: (word: string) => void;
}

export function WrongWordsPanel({
  wrongWords,
  onExport,
  onClear,
  onRemove,
}: WrongWordsPanelProps) {
  const colors = useThemeColors();
  const hasWrongWords = wrongWords.length > 0;

  return (
    <View style={[styles.container, { borderTopColor: colors.borderSubtle }]}>
      <View style={styles.header}>
        <Text style={[styles.title, { color: colors.muted }]}>错词本</Text>
        <View style={styles.actions}>
          <TouchableOpacity
            style={[styles.smallBtn, { borderColor: colors.border }]}
            onPress={onExport}
            activeOpacity={0.6}
          >
            <Text style={[styles.smallBtnText, { color: colors.secondary }]}>导出</Text>
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
      {!hasWrongWords ? (
        <View style={[styles.empty, { backgroundColor: colors.surfaceSunken }]}>
          <Text style={[styles.emptyText, { color: colors.subtle }]}>尚无错词</Text>
        </View>
      ) : (
        <View style={styles.chipRow}>
          {wrongWords.map((word) => (
            <TouchableOpacity
              key={word}
              style={[styles.chip, { backgroundColor: colors.surfaceRaised }]}
              onPress={() => onRemove(word)}
              activeOpacity={0.6}
            >
              <Text style={[styles.chipText, { color: colors.foreground, opacity: 0.8 }]}>
                {word}
              </Text>
              <Text style={[styles.chipRemove, { color: colors.subtle }]}> ×</Text>
            </TouchableOpacity>
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderTopWidth: 1,
    paddingTop: 16,
  },
  header: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 12,
  },
  title: {
    fontSize: 14,
    fontWeight: "500",
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
  empty: {
    borderRadius: radii.surface,
    paddingVertical: 20,
    alignItems: "center",
  },
  emptyText: {
    fontSize: 13,
  },
  chipRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 8,
    paddingBottom: 16,
  },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    paddingLeft: 16,
    paddingRight: 12,
    paddingVertical: 6,
    borderRadius: radii.full,
  },
  chipText: {
    fontSize: 14,
  },
  chipRemove: {
    fontSize: 16,
    lineHeight: 18,
  },
});
