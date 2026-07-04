import type { ReactNode } from "react";
import { StyleSheet, Text, TouchableOpacity, View } from "react-native";

import { radii } from "../lib/designTokens";
import { useThemeColors, type ThemeColors } from "../lib/theme";

interface ProgressCardProps {
  wordList: string[];
  currentIndex: number;
  playState: "idle" | "playing" | "paused";
  showWord: boolean;
  onToggleShowWord: () => void;
  markedFlash: boolean;
  wrongWords: string[];
}

export function ProgressCard({
  wordList,
  currentIndex,
  playState,
  showWord,
  onToggleShowWord,
  markedFlash,
  wrongWords,
}: ProgressCardProps) {
  const colors = useThemeColors();
  const isActive = playState === "playing" || playState === "paused";
  const isFinished = wordList.length > 0 && currentIndex >= wordList.length;
  const total = wordList.length;

  const currentPosition =
    total > 0
      ? Math.min(currentIndex + (isActive ? 1 : 0), total)
      : 0;

  const progressPct =
    total > 0
      ? (Math.min(currentIndex, total) / total) * 100
      : 0;

  const positionText = total > 0 ? `${currentPosition} / ${total}` : "0 / 0";

  const hasWrongWords = wrongWords.length > 0;
  const wrongWordsCount = wrongWords.length;

  const isHidden = isActive && !showWord && currentIndex < wordList.length;

  const displayWord: ReactNode = (() => {
    if (isFinished && playState === "idle") {
      return <Text style={[styles.wordCompleted, { color: colors.primary }]}>🎉 全部完成</Text>;
    }
    if (!isActive && wordList.length === 0) {
      return <Text style={[styles.wordIdle, { color: colors.subtle }]}>准备就绪</Text>;
    }
    if (currentIndex >= wordList.length) {
      return <Text style={[styles.wordIdle, { color: colors.subtle }]}>完成</Text>;
    }
    if (isHidden) {
      return <Text style={[styles.wordHidden, { color: colors.subtle }]}>• • •</Text>;
    }
    return (
      <Text style={[styles.wordText, { color: markedFlash ? colors.danger : colors.foreground }, markedFlash && styles.wordFlash]}>
        {wordList[currentIndex]}
      </Text>
    );
  })();

  return (
    <View style={[styles.card, { backgroundColor: colors.surfaceSunken, borderColor: colors.borderSubtle }]}>
      <View style={[styles.progressBar, { backgroundColor: colors.track }]}>
        <View style={[styles.progressFill, { width: `${progressPct}%`, backgroundColor: colors.primary }]} />
      </View>
      <View style={styles.content}>
        <View style={styles.topRow}>
          <Text style={[styles.positionText, { color: colors.muted }]}>
            {hasWrongWords ? (
              <Text>
                {currentPosition}
                {" / "}
                <Text style={{ color: colors.danger, fontWeight: "600" }}>{wrongWordsCount}</Text>
                {" / "}
                {total}
              </Text>
            ) : (
              positionText
            )}
          </Text>
          <TouchableOpacity
            style={[
              styles.toggleBtn,
              { borderColor: showWord ? colors.primary : colors.borderMuted, backgroundColor: showWord ? colors.primarySoft : colors.background },
            ]}
            onPress={onToggleShowWord}
            activeOpacity={0.7}
          >
            <Text style={[styles.toggleText, { color: showWord ? colors.primary : colors.muted }]}>
              {showWord ? "👁 显示中" : "🙈 已隐藏"}
            </Text>
          </TouchableOpacity>
        </View>
        <View style={styles.wordArea}>
          {displayWord}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderWidth: 1,
    borderRadius: radii.card,
    overflow: "hidden",
  },
  progressBar: {
    height: 4,
  },
  progressFill: {
    height: "100%",
    borderTopRightRadius: radii.full,
    borderBottomRightRadius: radii.full,
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 16,
  },
  topRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 8,
  },
  positionText: {
    fontSize: 20,
    fontVariant: ["tabular-nums"],
  },
  toggleBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: radii.full,
    borderWidth: 1,
    alignSelf: "flex-start",
  },
  toggleText: {
    fontSize: 14,
    fontWeight: "500",
  },
  wordArea: {
    minHeight: 80,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 8,
  },
  wordText: {
    fontSize: 36,
    fontWeight: "600",
    letterSpacing: -0.5,
    lineHeight: 44,
    textAlign: "center",
  },
  wordFlash: {
    transform: [{ scale: 1.05 }],
  },
  wordCompleted: {
    fontSize: 28,
    fontWeight: "600",
    textAlign: "center",
  },
  wordIdle: {
    fontSize: 20,
    fontWeight: "400",
    textAlign: "center",
  },
  wordHidden: {
    fontSize: 32,
    letterSpacing: 8,
    textAlign: "center",
  },
});
