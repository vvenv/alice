import type { ReactNode } from "react";
import { StyleSheet, Text, TouchableOpacity, View } from "react-native";

import { colors, radii } from "../lib/designTokens";

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
      return <Text style={styles.wordCompleted}>🎉 全部完成</Text>;
    }
    if (!isActive && wordList.length === 0) {
      return <Text style={styles.wordIdle}>准备就绪</Text>;
    }
    if (currentIndex >= wordList.length) {
      return <Text style={styles.wordIdle}>完成</Text>;
    }
    if (isHidden) {
      return <Text style={styles.wordHidden}>• • •</Text>;
    }
    return <Text style={[styles.wordText, markedFlash && styles.wordFlash]}>{wordList[currentIndex]}</Text>;
  })();

  return (
    <View style={styles.card}>
      <View style={styles.progressBar}>
        <View style={[styles.progressFill, { width: `${progressPct}%` }]} />
      </View>
      <View style={styles.content}>
        <View style={styles.topRow}>
          <Text style={styles.positionText}>
            {hasWrongWords ? (
              <Text>
                {currentPosition}
                {" / "}
                <Text style={styles.wrongCount}>{wrongWordsCount}</Text>
                {" / "}
                {total}
              </Text>
            ) : (
              positionText
            )}
          </Text>
          <TouchableOpacity
            style={[styles.toggleBtn, showWord && styles.toggleBtnActive]}
            onPress={onToggleShowWord}
            activeOpacity={0.7}
          >
            <Text style={[styles.toggleText, showWord && styles.toggleTextActive]}>
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
    backgroundColor: colors.surfaceSunken,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    borderRadius: radii.card,
    overflow: "hidden",
  },
  progressBar: {
    height: 4,
    backgroundColor: colors.track,
  },
  progressFill: {
    height: "100%",
    backgroundColor: colors.primary,
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
    color: colors.muted,
    fontVariant: ["tabular-nums"],
  },
  wrongCount: {
    color: colors.danger,
    fontWeight: "600",
  },
  toggleBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: radii.full,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    backgroundColor: colors.background,
    alignSelf: "flex-start",
  },
  toggleBtnActive: {
    backgroundColor: colors.primarySoft,
    borderColor: colors.primary,
  },
  toggleText: {
    fontSize: 14,
    fontWeight: "500",
    color: colors.muted,
  },
  toggleTextActive: {
    color: colors.primary,
    fontWeight: "600",
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
    color: colors.foreground,
    letterSpacing: -0.5,
    lineHeight: 44,
    textAlign: "center",
  },
  wordFlash: {
    color: colors.danger,
    transform: [{ scale: 1.05 }],
  },
  wordCompleted: {
    fontSize: 28,
    fontWeight: "600",
    color: colors.primary,
    textAlign: "center",
  },
  wordIdle: {
    fontSize: 20,
    fontWeight: "400",
    color: colors.subtle,
    textAlign: "center",
  },
  wordHidden: {
    fontSize: 32,
    letterSpacing: 8,
    color: colors.subtle,
    textAlign: "center",
  },
});
