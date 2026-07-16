import { Ionicons } from "@expo/vector-icons";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  Animated,
  Easing,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button, IconButton } from "../components/Button";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { CountdownRing } from "../components/CountdownRing";
import { PlaybackControls } from "../components/PlaybackControls";
import { Toast } from "../components/Toast";
import { usePlayback } from "../hooks/usePlayback";
import { useToast } from "../hooks/useToast";
import { useWrongWords } from "../hooks/useWrongWords";
import { parseWordLine, speakTextFromEntry } from "../lib/dictation";
import { fonts, radii, spacing } from "../lib/designTokens";
import { notifySuccess, notifyWarning } from "../lib/haptics";
import { useThemeColors } from "../lib/theme";

const STATUS_PLAYING = "#27ae60";
// react-native-web silently drops native-driver animations; fall back to JS there.
const USE_NATIVE_DRIVER = Platform.OS !== "web";

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
  const [exitDialogVisible, setExitDialogVisible] = useState(false);
  const [elapsedSec, setElapsedSec] = useState<number | null>(null);
  const startTimeRef = useRef(Date.now());
  const progressAnim = useRef(new Animated.Value(0)).current;
  const countdownAnim = useRef(new Animated.Value(0)).current;
  const prevRemainingRef = useRef<number | null>(null);
  const finishAnim = useRef(new Animated.Value(0)).current;

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

  // Start playback once on mount.
  useEffect(() => {
    playback.startDictation(words);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isActive =
    playback.playState === "playing" || playback.playState === "paused";

  const handlePlayToggle = useCallback(() => {
    if (playback.playState === "playing") {
      playback.pauseDictation();
    } else {
      playback.resumeDictation();
    }
  }, [playback]);

  // ---- Derived state ----
  const isFinished =
    playback.playState === "idle" && playback.wordList.length > 0;

  const markEnabled =
    isActive && playback.currentIndex < playback.wordList.length;
  const skipEnabled =
    isActive && playback.currentIndex < playback.wordList.length;

  const handleMarkWrong = useCallback(() => {
    if (!isActive || playback.currentIndex >= playback.wordList.length) return;
    const word = speakTextFromEntry(
      playback.wordList[playback.currentIndex]!,
    );
    notifyWarning();
    markWrong(word);
  }, [isActive, markWrong, playback.currentIndex, playback.wordList]);

  const handleExit = useCallback(() => {
    onEnd();
  }, [onEnd]);

  // Confirm before abandoning an in-progress session; exit directly otherwise.
  const requestStop = useCallback(() => {
    if (!isActive) {
      handleExit();
      return;
    }
    setExitDialogVisible(true);
  }, [isActive, handleExit]);

  const confirmStop = useCallback(() => {
    setExitDialogVisible(false);
    playback.stopDictation();
    handleExit();
  }, [handleExit, playback]);

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
  const countdownLabel =
    playback.remainingMs !== null
      ? `${(playback.remainingMs / 1000).toFixed(1)}s`
      : "—";

  // Animate the top progress bar between words instead of jumping.
  useEffect(() => {
    Animated.timing(progressAnim, {
      toValue: progress,
      duration: 300,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start();
  }, [progress, progressAnim]);

  // Drive the countdown bar with one linear animation per segment so it
  // depletes at 60fps, rather than re-rendering on every 50ms scheduler tick.
  useEffect(() => {
    const prev = prevRemainingRef.current;
    prevRemainingRef.current = playback.remainingMs;

    if (playback.remainingMs === null) {
      countdownAnim.stopAnimation();
      Animated.timing(countdownAnim, {
        toValue: 0,
        duration: 150,
        easing: Easing.out(Easing.quad),
        useNativeDriver: false,
      }).start();
      return;
    }
    // A value appearing or increasing marks the start of a new segment
    // (next word, resume, or the interval slider being adjusted mid-wait).
    if (prev === null || playback.remainingMs > prev) {
      countdownAnim.stopAnimation();
      countdownAnim.setValue(
        intervalMs > 0 ? Math.min(1, playback.remainingMs / intervalMs) : 0,
      );
      Animated.timing(countdownAnim, {
        toValue: 0,
        duration: playback.remainingMs,
        easing: Easing.linear,
        useNativeDriver: false,
      }).start();
    }
  }, [playback.remainingMs, intervalMs, countdownAnim]);

  // Completion: capture stats once, then celebrate.
  useEffect(() => {
    if (!isFinished || elapsedSec !== null) return;
    // The session can finish while the exit dialog is open; its "尚未完成"
    // message would be stale, so dismiss it.
    setExitDialogVisible(false);
    setElapsedSec(
      Math.max(1, Math.round((Date.now() - startTimeRef.current) / 1000)),
    );
    notifySuccess();
    Animated.spring(finishAnim, {
      toValue: 1,
      useNativeDriver: USE_NATIVE_DRIVER,
      friction: 6,
      tension: 60,
    }).start();
  }, [isFinished, elapsedSec, finishAnim]);

  // ---- Current word entry + meta for display (already enriched on Home) ----
  const currentLine =
    playback.currentIndex < playback.wordList.length
      ? playback.wordList[playback.currentIndex]!
      : "";
  const currentEntry = parseWordLine(currentLine);
  const currentMeta =
    currentEntry.pos || currentEntry.meaning
      ? { pos: currentEntry.pos, meaning: currentEntry.meaning }
      : null;

  const status = isFinished
    ? { label: "已完成", dot: STATUS_PLAYING }
    : playback.playState === "playing"
      ? { label: "听写中", dot: STATUS_PLAYING }
      : { label: "已暂停", dot: colors.gold };

  return (
    <SafeAreaView
      style={[styles.container, { backgroundColor: colors.background }]}
      edges={["top", "bottom", "left", "right"]}
    >
      <View style={[styles.progressBar, { backgroundColor: colors.track }]}>
        <Animated.View
          style={[
            styles.progressFill,
            {
              backgroundColor: colors.gold,
              width: progressAnim.interpolate({
                inputRange: [0, 1],
                outputRange: ["0%", "100%"],
              }),
            },
          ]}
        />
      </View>

      <View style={styles.header}>
        <View style={[styles.headerSide, styles.headerSideLeft]}>
          <IconButton
            icon="close"
            onPress={requestStop}
            accessibilityLabel="退出听写"
          />
        </View>

        <Text style={[styles.progressText, { color: colors.muted }]}>
          <Text style={styles.progressCurrent}>
            {playback.currentIndex + 1}
          </Text>
          {" / "}
          {playback.wordList.length}
        </Text>

        <View style={[styles.headerSide, styles.headerSideRight]}>
          <View
            style={[
              styles.statusPill,
              {
                backgroundColor: colors.surface,
                borderColor: colors.borderMuted,
              },
            ]}
            accessibilityLabel={status.label}
          >
            <View style={[styles.statusDot, { backgroundColor: status.dot }]} />
            <Text style={[styles.statusText, { color: colors.muted }]}>
              {status.label}
            </Text>
          </View>
        </View>
      </View>

      <View style={styles.wordStage}>
        {isFinished ? (
          <Animated.View
            style={[
              styles.finishedContainer,
              {
                opacity: finishAnim,
                transform: [
                  {
                    scale: finishAnim.interpolate({
                      inputRange: [0, 1],
                      outputRange: [0.85, 1],
                    }),
                  },
                ],
              },
            ]}
          >
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
              <View
                style={[styles.statsRow, { borderTopColor: colors.borderMuted }]}
              >
                <View style={styles.statItem}>
                  <Text style={[styles.statValue, { color: colors.foreground }]}>
                    {playback.wordList.length}
                  </Text>
                  <Text style={[styles.statLabel, { color: colors.muted }]}>
                    单词
                  </Text>
                </View>
                <View style={styles.statItem}>
                  <Text
                    style={[
                      styles.statValue,
                      {
                        color:
                          wrongWords.length > 0
                            ? colors.danger
                            : colors.foreground,
                      },
                    ]}
                  >
                    {wrongWords.length}
                  </Text>
                  <Text style={[styles.statLabel, { color: colors.muted }]}>
                    错词
                  </Text>
                </View>
                <View style={styles.statItem}>
                  <Text style={[styles.statValue, { color: colors.foreground }]}>
                    {elapsedSec !== null
                      ? `${Math.floor(elapsedSec / 60)}:${String(elapsedSec % 60).padStart(2, "0")}`
                      : "—"}
                  </Text>
                  <Text style={[styles.statLabel, { color: colors.muted }]}>
                    用时
                  </Text>
                </View>
              </View>
            </View>

            <Button
              label="返回首页"
              icon="arrow-back"
              variant="primary"
              size="md"
              onPress={handleExit}
              style={styles.returnBtn}
            />
          </Animated.View>
        ) : (
          <>
            <View style={styles.watchWrap}>
              <CountdownRing
                size={288}
                strokeWidth={7}
                progress={countdownAnim}
                color={colors.gold}
                trackColor={colors.track}
                ticks={12}
                tickColor={colors.borderMuted}
              >
                <View
                  style={[
                    styles.dial,
                    {
                      backgroundColor: markedFlash
                        ? colors.dangerSoft
                        : colors.surfaceRaised,
                      borderColor: markedFlash
                        ? colors.danger
                        : colors.borderSubtle,
                    },
                  ]}
                >
                  {showWord &&
                  playback.currentIndex < playback.wordList.length ? (
                    <View style={styles.wordRevealContent}>
                      <Text
                        style={[styles.wordText, { color: colors.foreground }]}
                        numberOfLines={2}
                        adjustsFontSizeToFit
                      >
                        {currentEntry.word}
                      </Text>
                      {currentMeta &&
                        (currentMeta.pos || currentMeta.meaning) && (
                          <Text
                            style={[styles.wordMeta, { color: colors.muted }]}
                            numberOfLines={2}
                          >
                            {currentMeta.pos ? `${currentMeta.pos} ` : ""}
                            {currentMeta.meaning ?? ""}
                          </Text>
                        )}
                    </View>
                  ) : (
                    <Text style={[styles.wordText, { color: colors.foreground }]}>
                      {"•••••"}
                    </Text>
                  )}
                  <Text
                    style={[
                      styles.dialCountdown,
                      { color: colors.gold },
                      (!isActive || !autoNext || playback.remainingMs === null) &&
                        styles.dialCountdownHidden,
                    ]}
                  >
                    {countdownLabel}
                  </Text>
                </View>
              </CountdownRing>

              <IconButton
                icon={showWord ? "eye" : "eye-off"}
                onPress={() => setShowWord((v) => !v)}
                accessibilityLabel={showWord ? "隐藏单词" : "显示单词"}
                style={styles.eyeBtn}
              />
            </View>

            <Button
              label="标记错词"
              icon="close-circle-outline"
              variant="danger"
              size="md"
              onPress={handleMarkWrong}
              disabled={!markEnabled}
              haptic={false}
              style={styles.markBtn}
            />

            {showWord &&
              playback.currentIndex + 1 < playback.wordList.length && (
                <View style={styles.nextWordRow}>
                  <Text style={[styles.nextWordLabel, { color: colors.muted }]}>
                    下一个
                  </Text>
                  <Text style={[styles.nextWordText, { color: colors.subtle }]}>
                    {parseWordLine(
                      playback.wordList[playback.currentIndex + 1]!,
                    ).word}
                  </Text>
                </View>
              )}
          </>
        )}
      </View>

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

        <View style={styles.controlRow}>
          <View style={[styles.controlItem, styles.controlItemSide]}>
            <IconButton
              icon="stop"
              size={48}
              variant="danger"
              onPress={requestStop}
              disabled={!isActive}
              accessibilityLabel="结束"
            />
            <Text style={[styles.controlLabel, { color: colors.muted }]}>
              结束
            </Text>
          </View>
          <View style={styles.controlItem}>
            <IconButton
              icon={playback.playState === "playing" ? "pause" : "play"}
              size={64}
              variant="primary"
              onPress={handlePlayToggle}
              accessibilityLabel={
                playback.playState === "playing" ? "暂停" : "继续"
              }
            />
            <Text style={[styles.controlLabel, { color: colors.muted }]}>
              {playback.playState === "playing" ? "暂停" : "继续"}
            </Text>
          </View>
          <View style={[styles.controlItem, styles.controlItemSide]}>
            <IconButton
              icon="play-skip-forward"
              size={48}
              variant="surface"
              onPress={playback.skipToNextWord}
              disabled={!skipEnabled}
              accessibilityLabel="跳过"
            />
            <Text style={[styles.controlLabel, { color: colors.muted }]}>
              跳过
            </Text>
          </View>
        </View>

        <View style={styles.wrongSection}>
          <View style={styles.wrongHeader}>
            <Text style={[styles.wrongTitle, { color: colors.muted }]}>
              错词本 ({wrongWords.length})
            </Text>
            <View style={styles.wrongActions}>
              <Button label="导出" variant="ghost" size="sm" onPress={handleExport} />
              <Button
                label="清空"
                variant="ghost"
                size="sm"
                onPress={handleClearWrong}
              />
            </View>
          </View>
          {wrongWords.length === 0 ? (
            <Text
              style={[
                styles.emptyWrong,
                { color: colors.subtle, backgroundColor: colors.surface },
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

      <ConfirmDialog
        visible={exitDialogVisible}
        title="结束听写"
        message="当前听写尚未完成，确定要结束并返回吗？"
        confirmLabel="结束"
        destructive
        onConfirm={confirmStop}
        onCancel={() => setExitDialogVisible(false)}
      />
      <Toast message={toast} />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  progressBar: { height: 4 },
  progressFill: { height: "100%", borderBottomRightRadius: 2 },

  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  headerSide: {
    minWidth: 80,
    flexDirection: "row",
    alignItems: "center",
  },
  headerSideLeft: {
    justifyContent: "flex-start",
  },
  headerSideRight: {
    justifyContent: "flex-end",
  },
  statusPill: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.xs + 2,
    height: 28,
    paddingHorizontal: spacing.md,
    borderRadius: radii.full,
    borderWidth: 1,
  },
  statusDot: {
    width: 7,
    height: 7,
    borderRadius: radii.full,
  },
  statusText: {
    fontSize: 12,
    fontWeight: "600",
  },
  progressText: {
    fontSize: 15,
    fontWeight: "500",
    fontVariant: ["tabular-nums"],
    textAlign: "center",
  },
  progressCurrent: {
    fontFamily: fonts.display,
    fontSize: 17,
    fontWeight: "700",
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
  watchWrap: {
    alignItems: "center",
    justifyContent: "center",
  },
  dial: {
    width: 288 - 7 * 2 - 24,
    height: 288 - 7 * 2 - 24,
    borderRadius: radii.full,
    borderWidth: 1,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: spacing.xl,
    gap: spacing.sm,
  },
  dialCountdown: {
    fontFamily: fonts.display,
    fontSize: 14,
    fontWeight: "700",
    fontVariant: ["tabular-nums"],
  },
  dialCountdownHidden: {
    opacity: 0,
  },
  eyeBtn: {
    position: "absolute",
    top: 0,
    right: 12,
  },
  wordText: {
    fontFamily: fonts.display,
    fontSize: 36,
    fontWeight: "700",
    letterSpacing: 1,
    textAlign: "center",
  },
  wordRevealContent: {
    alignItems: "center",
    gap: spacing.xs,
  },
  wordMeta: {
    fontSize: 15,
    fontWeight: "400",
    textAlign: "center",
  },

  bottomPanel: {
    borderTopWidth: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.md,
    gap: spacing.lg,
  },

  controlRow: {
    flexDirection: "row",
    alignItems: "flex-start",
    justifyContent: "center",
    gap: spacing["2xl"] + spacing.lg,
  },
  controlItem: {
    alignItems: "center",
    gap: spacing.xs + 2,
    minWidth: 64,
  },
  controlItemSide: {
    paddingTop: 8,
  },
  controlLabel: {
    fontSize: 12,
    fontWeight: "600",
  },
  markBtn: {
    width: "100%",
    maxWidth: 288,
  },
  nextWordRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
  },
  nextWordLabel: { fontSize: 12, fontWeight: "500" },
  nextWordText: { fontSize: 16, fontWeight: "600" },
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
  },
  finishedTitle: { fontFamily: fonts.display, fontSize: 22, fontWeight: "700" },
  statsRow: {
    flexDirection: "row",
    alignSelf: "stretch",
    borderTopWidth: StyleSheet.hairlineWidth,
    marginTop: spacing.xs,
    paddingTop: spacing.lg,
    paddingHorizontal: spacing.lg,
  },
  statItem: {
    flex: 1,
    alignItems: "center",
    gap: 2,
  },
  statValue: {
    fontFamily: fonts.display,
    fontSize: 22,
    fontWeight: "700",
    fontVariant: ["tabular-nums"],
  },
  statLabel: {
    fontSize: 12,
    fontWeight: "500",
  },
  returnBtn: {
    width: "100%",
    maxWidth: 320,
  },

  wrongSection: { gap: spacing.sm, maxHeight: 120 },
  wrongHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  wrongTitle: { fontSize: 13, fontWeight: "600" },
  wrongActions: { flexDirection: "row", gap: spacing.sm },
  emptyWrong: {
    textAlign: "center",
    fontSize: 13,
    paddingVertical: spacing.md,
    borderRadius: radii.surface,
  },
  wrongScroll: { flexGrow: 0 },
  chipRow: { flexDirection: "row", flexWrap: "wrap", gap: spacing.sm },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    borderWidth: 1,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs + 2,
    borderRadius: radii.full,
  },
  chipText: { fontSize: 13 },
  chipRemove: { fontSize: 14 },
});
