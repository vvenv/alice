import { StyleSheet, Text, TouchableOpacity, View } from "react-native";

import { colors, radii } from "../lib/designTokens";

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
  const hasWrongWords = wrongWords.length > 0;

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>错词本</Text>
        <View style={styles.actions}>
          <TouchableOpacity style={styles.smallBtn} onPress={onExport} activeOpacity={0.6}>
            <Text style={styles.smallBtnText}>导出</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.smallBtn} onPress={onClear} activeOpacity={0.6}>
            <Text style={styles.smallBtnText}>清空</Text>
          </TouchableOpacity>
        </View>
      </View>
      {!hasWrongWords ? (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>尚无错词</Text>
        </View>
      ) : (
        <View style={styles.chipRow}>
          {wrongWords.map((word) => (
            <TouchableOpacity
              key={word}
              style={styles.chip}
              onPress={() => onRemove(word)}
              activeOpacity={0.6}
            >
              <Text style={styles.chipText}>{word}</Text>
              <Text style={styles.chipRemove}> ×</Text>
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
    borderTopColor: colors.borderSubtle,
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
    color: colors.muted,
  },
  actions: {
    flexDirection: "row",
    gap: 8,
  },
  smallBtn: {
    borderRadius: radii.full,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: 12,
    paddingVertical: 4,
  },
  smallBtnText: {
    fontSize: 12,
    fontWeight: "500",
    color: colors.secondary,
  },
  empty: {
    backgroundColor: colors.surfaceSunken,
    borderRadius: radii.surface,
    paddingVertical: 20,
    alignItems: "center",
  },
  emptyText: {
    fontSize: 13,
    color: colors.subtle,
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
    backgroundColor: colors.surfaceRaised,
    paddingLeft: 16,
    paddingRight: 12,
    paddingVertical: 6,
    borderRadius: radii.full,
  },
  chipText: {
    fontSize: 14,
    color: colors.foreground,
    opacity: 0.8,
  },
  chipRemove: {
    fontSize: 16,
    color: colors.subtle,
    lineHeight: 18,
  },
});
