import { useCallback, useEffect, useState } from "react";
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { PlaybackControls } from "../components/PlaybackControls";
import { usePlayback } from "../hooks/usePlayback";
import { useToast } from "../hooks/useToast";
import { useWrongWords } from "../hooks/useWrongWords";
import { initAudio } from "../lib/tts";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

interface DictationScreenProps {
  words: string[];
  intervalSec: number;
  autoNext: boolean;
  onEnd: () => void;
}

export function DictationScreen({
  words,
  intervalSec: initialIntervalSec,
  autoNext: initialAutoNext,
  onEnd,
}: DictationScreenProps) {
  const colors = useThemeColors();
  const [showWord, setShowWord] = useState(false);
  const [intervalSec, setIntervalSec] = useState(initialIntervalSec);
  const [autoNext, setAutoNext] = useState(initialAutoNext);

  const { toast, showToast } = useToast();
  const {
    wrongWords,
    markedFlash,
    markWrong,
    exportWrong,
    clearWrong,
    removeWrongWord,
  } = useWrongWords();

  const playback = usePlayback({ intervalSec, autoNext });

  // Initialize audio then auto-start on mount
  useEffect(() => {
    let cancelled = false;
    (async () => {
      await initAudio();
      if (cancelled) return;
      playback.startDictation(words);
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isActive =
    playback.playState === "playing" || playback.playState === "paused";
  const markEnabled =
    isActive && playback.currentIndex < playback.wordList.length;
  const skipEnabled =
    isActive && playback.currentIndex < playback.wordList.length;

  const handleMarkWrong = useCallback(() => {
    if (!isActive || playback.currentIndex >= playback.wordList.length) return;
    markWrong(playback.wordList[playback.currentIndex]!);
  }, [isActive, markWrong, playback.currentIndex, playback.wordList]);

  const handlePlayToggle = useCallback(() => {
    if (playback.playState === "playing") {
      playback.pauseDictation();
      return;
    }
    playback.resumeDictation();
  }, [playback]);

  const handleStop = useCallback(() => {
    playback.stopDictation();
    onEnd();
  }, [playback, onEnd]);

  const handleExport = useCallback(async () => {
    const msg = await exportWrong();
    if (msg) showToast(msg);
  }, [exportWrong, showToast]);

  const handleClearWrong = useCallback(() => {
    if (wrongWords.length === 0) return;
    clearWrong();
    showToast("已清空错词本");
  }, [wrongWords, clearWrong, showToast]);

  const progress =
    playback.wordList.length > 0
      ? (playback.currentIndex + 1) / playback.wordList.length
      : 0;

  const intervalMs = intervalSec * 1000;
  const countdownScale =
    playback.remainingMs !== null && intervalMs > 0
      ? playback.remainingMs / intervalMs
      : 0;
  const countdownLabel =
    playback.remainingMs !== null
      ? `${Math.ceil(playback.remainingMs / 1000)}s`
      : "—";

  const stateLabel =
    playback.playState === "playing"
      ? "播放中"
      : playback.playState === "paused"
        ? "已暂停"
        : "已结束";

  return (
    <SafeAreaView
      style={[styles.container, { backgroundColor: colors.background }]}
      edges={["top", "bottom"]}
    >
      <View style={[styles.progressBar, { backgroundColor: colors.track }]}>
        <View
          style={[
            styles.progressFill,
            { width: `${progress * 100}%`, backgroundColor: colors.primary },
          ]}
        />
      </View>

      {/* Progress indicator */}
      <View style={styles.header}>
        <Text style={[styles.progressText, { color: colors.muted }]}>
          {playback.currentIndex + 1} / {playback.wordList.length}
        </Text>
      </View>

      {/* Word card — centered in remaining space */}
      <View style={styles.wordStage}>
        <View
          style={[
            styles.wordCard,
            {
              backgroundColor: colors.surfaceRaised,
              borderColor: colors.borderSubtle,
            },
            markedFlash && {
              backgroundColor: colors.dangerSoft,
              borderColor: colors.danger,
            },
          ]}
        >
          <TouchableOpacity
            style={[
              styles.toggleWordBtn,
              {
                borderColor: showWord ? colors.primary : colors.borderMuted,
                backgroundColor: showWord
                  ? colors.primarySoft
                  : colors.surface,
              },
            ]}
            onPress={() => setShowWord((v) => !v)}
            activeOpacity={0.7}
            accessibilityLabel={showWord ? "隐藏单词" : "显示单词"}
          >
            <Text style={styles.toggleWordIcon}>
              {showWord ? "👁" : "🙈"}
            </Text>
          </TouchableOpacity>

          <Text style={[styles.wordText, { color: colors.foreground }]}>
            {showWord && playback.currentIndex < playback.wordList.length
              ? playback.wordList[playback.currentIndex]!
              : "•••••"}
          </Text>
        </View>

        <TouchableOpacity
          style={[
            styles.markBtn,
            {
              borderColor: colors.borderMuted,
              backgroundColor: colors.surface,
            },
            !markEnabled && styles.controlBtnDisabled,
          ]}
          onPress={handleMarkWrong}
          disabled={!markEnabled}
          activeOpacity={0.7}
        >
          <Text style={[styles.markBtnText, { color: colors.dangerMuted }]}>
            ✕ 标记错词
          </Text>
        </TouchableOpacity>
      </View>

      {/* Bottom panel — settings, controls, wrong words */}
      <View
        style={[
          styles.bottomPanel,
          {
            backgroundColor: colors.surfaceSunken,
            borderTopColor: colors.borderSubtle,
          },
        ]}
      >
        <PlaybackControls
          intervalSec={intervalSec}
          autoNext={autoNext}
          onIntervalChange={setIntervalSec}
          onAutoNextChange={setAutoNext}
          showPlayButton={false}
        />

        {isActive && autoNext ? (
          <View style={styles.countdownSection}>
            <View
              style={[styles.countdownBar, { backgroundColor: colors.track }]}
            >
              <View
                style={[
                  styles.countdownFill,
                  {
                    width: `${countdownScale * 100}%`,
                    backgroundColor: colors.primary,
                  },
                ]}
              />
            </View>
            <Text style={[styles.countdownText, { color: colors.primary }]}>
              {countdownLabel}
            </Text>
          </View>
        ) : null}

        <View style={styles.actionSection}>
          <View style={styles.stateIndicator}>
            <View
              style={[
                styles.stateDot,
                { backgroundColor: colors.subtle },
                playback.playState === "playing" && {
                  backgroundColor: "#27ae60",
                },
                playback.playState === "paused" && {
                  backgroundColor: "#f39c12",
                },
              ]}
            />
            <Text style={[styles.stateText, { color: colors.muted }]}>
              {stateLabel}
            </Text>
          </View>

          <View style={styles.controlRow}>
            <TouchableOpacity
              style={[
                styles.controlBtn,
                { backgroundColor: colors.primary, borderColor: colors.primary },
              ]}
              onPress={handlePlayToggle}
              activeOpacity={0.7}
            >
              <Text style={[styles.controlBtnText, { color: colors.background }]}>
                {playback.playState === "playing" ? "⏸ 暂停" : "▶ 继续"}
              </Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[
                styles.controlBtn,
                {
                  backgroundColor: colors.background,
                  borderColor: colors.border,
                },
                !skipEnabled && styles.controlBtnDisabled,
              ]}
              onPress={playback.skipToNextWord}
              disabled={!skipEnabled}
              activeOpacity={0.7}
            >
              <Text style={[styles.controlBtnTextOutline, { color: colors.secondary }]}>
                ⏭ 跳过
              </Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[
                styles.controlBtn,
                {
                  backgroundColor: colors.background,
                  borderColor: colors.dangerMuted,
                },
                !isActive && styles.controlBtnDisabled,
              ]}
              onPress={handleStop}
              disabled={!isActive}
              activeOpacity={0.7}
            >
              <Text style={[styles.controlBtnTextDanger, { color: colors.danger }]}>
                ⏹ 结束
              </Text>
            </TouchableOpacity>
          </View>
        </View>

        <View style={styles.wrongSection}>
          <View style={styles.wrongHeader}>
            <Text style={[styles.wrongTitle, { color: colors.muted }]}>
              错词本 ({wrongWords.length})
            </Text>
            <View style={styles.wrongActions}>
              <TouchableOpacity
                style={[styles.smallBtn, { backgroundColor: colors.surface }]}
                onPress={handleExport}
              >
                <Text style={[styles.smallBtnText, { color: colors.secondary }]}>
                  导出
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.smallBtn, { backgroundColor: colors.surface }]}
                onPress={handleClearWrong}
              >
                <Text style={[styles.smallBtnText, { color: colors.secondary }]}>
                  清空
                </Text>
              </TouchableOpacity>
            </View>
          </View>
          {wrongWords.length === 0 ? (
            <Text
              style={[
                styles.emptyWrong,
                {
                  color: colors.subtle,
                  backgroundColor: colors.surface,
                },
              ]}
            >
              尚无错词
            </Text>
          ) : (
            <ScrollView
              style={styles.wrongScroll}
              contentContainerStyle={styles.chipRow}
              nestedScrollEnabled
              showsVerticalScrollIndicator={false}
            >
              {wrongWords.map((word) => (
                <TouchableOpacity
                  key={word}
                  style={[
                    styles.chip,
                    {
                      backgroundColor: colors.background,
                      borderColor: colors.borderMuted,
                    },
                  ]}
                  onPress={() => removeWrongWord(word)}
                  activeOpacity={0.7}
                >
                  <Text style={[styles.chipText, { color: colors.foreground }]}>
                    {word}
                  </Text>
                  <Text style={[styles.chipRemove, { color: colors.subtle }]}>
                    {" "}×
                  </Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
          )}
        </View>
      </View>

      {toast ? (
        <View style={styles.toast}>
          <Text style={styles.toastText}>{toast}</Text>
        </View>
      ) : null}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  progressBar: {
    height: 3,
  },
  progressFill: {
    height: "100%",
  },

  header: {
    alignItems: "center",
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  progressText: {
    fontSize: 15,
    fontWeight: "600",
    fontVariant: ["tabular-nums"],
    textAlign: "center",
  },
  toggleWordBtn: {
    position: "absolute",
    top: spacing.md,
    right: spacing.md,
    width: 36,
    height: 36,
    borderRadius: radii.full,
    borderWidth: 1,
    justifyContent: "center",
    alignItems: "center",
    zIndex: 1,
  },
  toggleWordIcon: {
    fontSize: 16,
  },

  wordStage: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    minHeight: 120,
    gap: spacing.lg,
  },
  wordCard: {
    width: "100%",
    maxWidth: 360,
    borderRadius: radii.card,
    paddingHorizontal: spacing["2xl"],
    paddingVertical: spacing["2xl"],
    alignItems: "center",
    borderWidth: 1,
    shadowColor: "#000",
    shadowOpacity: 0.05,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  wordText: {
    fontSize: 40,
    fontWeight: "700",
    letterSpacing: 1,
    textAlign: "center",
  },

  bottomPanel: {
    borderTopWidth: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.md,
    gap: spacing.lg,
  },

  countdownSection: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    marginTop: -spacing.sm,
  },
  countdownBar: {
    flex: 1,
    height: 6,
    borderRadius: radii.xs,
    overflow: "hidden",
  },
  countdownFill: {
    height: "100%",
    borderRadius: radii.xs,
  },
  countdownText: {
    fontSize: 13,
    fontWeight: "700",
    minWidth: 32,
    textAlign: "right",
    fontVariant: ["tabular-nums"],
  },

  actionSection: {
    gap: spacing.md,
  },
  stateIndicator: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.sm,
  },
  stateDot: {
    width: 7,
    height: 7,
    borderRadius: radii.full,
  },
  stateText: {
    fontSize: 13,
    fontWeight: "500",
  },

  controlRow: {
    flexDirection: "row",
    gap: spacing.sm,
  },
  controlBtn: {
    flex: 1,
    height: 46,
    borderRadius: radii.control,
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 1.5,
  },
  controlBtnDisabled: {
    opacity: 0.4,
  },
  controlBtnText: {
    fontSize: 14,
    fontWeight: "600",
  },
  controlBtnTextOutline: {
    fontSize: 14,
    fontWeight: "600",
  },
  controlBtnTextDanger: {
    fontSize: 14,
    fontWeight: "600",
  },
  markBtn: {
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.lg,
    borderRadius: radii.full,
    borderWidth: 1,
  },
  markBtnText: {
    fontSize: 13,
    fontWeight: "600",
  },

  wrongSection: {
    gap: spacing.sm,
    maxHeight: 120,
  },
  wrongHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  wrongTitle: {
    fontSize: 13,
    fontWeight: "600",
  },
  wrongActions: {
    flexDirection: "row",
    gap: spacing.sm,
  },
  smallBtn: {
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    borderRadius: radii.xs,
  },
  smallBtnText: {
    fontSize: 12,
    fontWeight: "500",
  },
  emptyWrong: {
    textAlign: "center",
    fontSize: 13,
    paddingVertical: spacing.md,
    borderRadius: radii.surface,
  },
  wrongScroll: {
    flexGrow: 0,
  },
  chipRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: spacing.sm,
  },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    borderWidth: 1,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs + 2,
    borderRadius: radii.full,
  },
  chipText: {
    fontSize: 13,
  },
  chipRemove: {
    fontSize: 14,
  },

  toast: {
    position: "absolute",
    bottom: 40,
    left: spacing.lg,
    right: spacing.lg,
    backgroundColor: "rgba(0,0,0,0.8)",
    paddingVertical: spacing.md,
    borderRadius: radii.surface,
    alignItems: "center",
  },
  toastText: {
    color: "#fff",
    fontSize: 14,
  },
});
