import { Ionicons } from "@expo/vector-icons";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { PlaybackControls } from "../components/PlaybackControls";
import { Toast } from "../components/Toast";
import { useBackgroundAudio } from "../hooks/useBackgroundAudio";
import { usePlayback } from "../hooks/usePlayback";
import { useToast } from "../hooks/useToast";
import { useWrongWords } from "../hooks/useWrongWords";
import { initAudio } from "../lib/tts";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

const STATUS_PLAYING = "#27ae60";
const STATUS_PAUSED = "#f39c12";

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

  // Ref to hold setPlaying from useBackgroundAudio (avoids circular dependency)
  const setPlayingRef = useRef<(playing: boolean) => void>(() => {});

  const playback = usePlayback({ intervalSec, autoNext });

  // In-app play/pause — used both by the UI button AND the lock-screen callback
  const handlePlayToggle = useCallback(() => {
    const isPlaying = playback.playState === "playing";
    if (isPlaying) {
      playback.pauseDictation();
      setPlayingRef.current(false);
      return;
    }
    playback.resumeDictation();
    setPlayingRef.current(true);
  }, [playback]);

  // Ref-based callbacks so useBackgroundAudio never reads stale props
  const remoteCallbacksRef = useRef({
    onTogglePlayPause: handlePlayToggle,
    onSkipToNext: playback.skipToNextWord,
    onSkipToPrevious: () => {
      playback.pauseDictation();
      playback.resumeDictation();
    },
  });

  // Keep the ref up to date whenever dependencies change
  useEffect(() => {
    remoteCallbacksRef.current.onTogglePlayPause = handlePlayToggle;
    remoteCallbacksRef.current.onSkipToNext = playback.skipToNextWord;
    remoteCallbacksRef.current.onSkipToPrevious = () => {
      playback.pauseDictation();
      playback.resumeDictation();
    };
  }, [handlePlayToggle, playback.skipToNextWord, playback.pauseDictation, playback.resumeDictation]);

  const { startSession, setPlaying, updateMetadata, stopSession } =
    useBackgroundAudio(remoteCallbacksRef);

  // Wire up setPlayingRef so handlePlayToggle can call setPlaying
  useEffect(() => {
    setPlayingRef.current = setPlaying;
  }, [setPlaying]);

  // Initialize audio then auto-start on mount
  useEffect(() => {
    let cancelled = false;
    (async () => {
      await initAudio();
      if (cancelled) return;
      startSession(true);
      playback.startDictation(words);
    })();
    return () => {
      cancelled = true;
      stopSession();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isActive =
    playback.playState === "playing" || playback.playState === "paused";
  const isFinished =
    playback.playState === "idle" && playback.wordList.length > 0;

  // Stop background audio session when dictation finishes naturally.
  useEffect(() => {
    if (isFinished) {
      stopSession();
    }
  }, [isFinished, stopSession]);

  // Update lock screen metadata when current word changes
  useEffect(() => {
    if (isActive && playback.wordList.length > 0) {
      const word = playback.wordList[playback.currentIndex];
      if (word) {
        updateMetadata(
          `${playback.currentIndex + 1} / ${playback.wordList.length}  ${word}`,
        );
      }
    }
  }, [
    playback.currentIndex,
    playback.wordList,
    isActive,
    updateMetadata,
  ]);

  const markEnabled =
    isActive && playback.currentIndex < playback.wordList.length;
  const skipEnabled =
    isActive && playback.currentIndex < playback.wordList.length;

  const handleMarkWrong = useCallback(() => {
    if (!isActive || playback.currentIndex >= playback.wordList.length) return;
    markWrong(playback.wordList[playback.currentIndex]!);
  }, [isActive, markWrong, playback.currentIndex, playback.wordList]);

  const handleStop = useCallback(() => {
    playback.stopDictation();
    stopSession();
    onEnd();
  }, [playback, stopSession, onEnd]);

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
      ? `${(playback.remainingMs / 1000).toFixed(1)}s`
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
      edges={["top", "bottom", "left", "right"]}
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

      {/* Word card / Finished view — centered in remaining space */}
      <View style={styles.wordStage}>
        {isFinished ? (
          <View style={styles.finishedContainer}>
            <View
              style={[
                styles.finishedCard,
                {
                  backgroundColor: colors.surfaceRaised,
                  borderColor: colors.borderSubtle,
                },
              ]}
            >
              <Ionicons
                name="checkmark-circle"
                size={48}
                color={STATUS_PLAYING}
              />
              <Text style={[styles.finishedTitle, { color: colors.foreground }]}>
                听写完成
              </Text>
              <Text style={[styles.finishedSub, { color: colors.muted }]}>
                共 {playback.wordList.length} 个单词
              </Text>
            </View>

            <TouchableOpacity
              style={[
                styles.returnBtn,
                { backgroundColor: colors.primary },
              ]}
              onPress={onEnd}
              activeOpacity={0.7}
            >
              <View style={styles.returnBtnContent}>
                <Ionicons
                  name="arrow-back"
                  size={18}
                  color={colors.background}
                />
                <Text
                  style={[
                    styles.returnBtnText,
                    { color: colors.background },
                  ]}
                >
                  返回首页
                </Text>
              </View>
            </TouchableOpacity>
          </View>
        ) : (
          <>
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
                <Ionicons
                  name={showWord ? "eye" : "eye-off"}
                  size={18}
                  color={showWord ? colors.primary : colors.muted}
                />
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
              <View style={styles.markBtnContent}>
                <Ionicons name="close" size={14} color={colors.dangerMuted} />
                <Text style={[styles.markBtnText, { color: colors.dangerMuted }]}>
                  标记错词
                </Text>
              </View>
            </TouchableOpacity>

            {showWord &&
              playback.currentIndex + 1 < playback.wordList.length && (
                <View style={styles.nextWordRow}>
                  <Text style={[styles.nextWordLabel, { color: colors.muted }]}>
                    下一个
                  </Text>
                  <Text style={[styles.nextWordText, { color: colors.subtle }]}>
                    {playback.wordList[playback.currentIndex + 1]}
                  </Text>
                </View>
              )}
          </>
        )}
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
                  backgroundColor: STATUS_PLAYING,
                },
                playback.playState === "paused" && {
                  backgroundColor: STATUS_PAUSED,
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
              <View style={styles.controlBtnContent}>
                <Ionicons
                  name={playback.playState === "playing" ? "pause" : "play"}
                  size={16}
                  color={colors.background}
                />
                <Text style={[styles.controlBtnText, { color: colors.background }]}>
                  {playback.playState === "playing" ? "暂停" : "继续"}
                </Text>
              </View>
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
              <View style={styles.controlBtnContent}>
                <Ionicons name="play-skip-forward" size={16} color={colors.secondary} />
                <Text style={[styles.controlBtnTextOutline, { color: colors.secondary }]}>
                  跳过
                </Text>
              </View>
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
              <View style={styles.controlBtnContent}>
                <Ionicons name="stop" size={16} color={colors.danger} />
                <Text style={[styles.controlBtnTextDanger, { color: colors.danger }]}>
                  结束
                </Text>
              </View>
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

      <Toast message={toast} />
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
    minHeight: 120,
    borderRadius: radii.card,
    alignItems: "center",
    justifyContent: "center",
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
  controlBtnContent: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.xs,
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
  markBtnContent: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.xs,
  },
  markBtnText: {
    fontSize: 13,
    fontWeight: "600",
  },
  nextWordRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
  },
  nextWordLabel: {
    fontSize: 12,
    fontWeight: "500",
  },
  nextWordText: {
    fontSize: 16,
    fontWeight: "600",
  },
  finishedContainer: {
    alignItems: "center",
    gap: spacing["2xl"],
    width: "100%",
  },
  finishedCard: {
    width: "100%",
    maxWidth: 320,
    minHeight: 180,
    borderRadius: radii.card,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: 1,
    gap: spacing.md,
    shadowColor: "#000",
    shadowOpacity: 0.05,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  finishedTitle: {
    fontSize: 22,
    fontWeight: "700",
  },
  finishedSub: {
    fontSize: 14,
  },
  returnBtn: {
    width: "100%",
    maxWidth: 320,
    height: 48,
    borderRadius: radii.control,
    justifyContent: "center",
    alignItems: "center",
  },
  returnBtnContent: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
  },
  returnBtnText: {
    fontSize: 16,
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
});
