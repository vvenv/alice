import { useCallback, useEffect, useState } from "react";
import {
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { usePlayback } from "../hooks/usePlayback";
import { useToast } from "../hooks/useToast";
import { useWrongWords } from "../hooks/useWrongWords";
import { initAudio } from "../lib/tts";

interface DictationScreenProps {
  words: string[];
  voice: string;
  intervalSec: number;
  autoNext: boolean;
  onEnd: () => void;
  brokenWords: string[];
}

export function DictationScreen({
  words,
  voice,
  intervalSec,
  autoNext,
  onEnd,
  brokenWords,
}: DictationScreenProps) {
  const [showWord, setShowWord] = useState(false);

  const { toast, showToast } = useToast();
  const { wrongWords, markedFlash, markWrong, exportWrong, clearWrong, removeWrongWord } =
    useWrongWords(brokenWords);

  const playback = usePlayback({ intervalSec, autoNext, voice });

  // Initialize audio then auto-start on mount
  useEffect(() => {
    let cancelled = false;
    (async () => {
      await initAudio();
      if (cancelled) return;
      playback.startDictation(words);
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isActive = playback.playState === "playing" || playback.playState === "paused";
  const markEnabled = isActive && playback.currentIndex < playback.wordList.length;
  const skipEnabled = isActive && playback.currentIndex < playback.wordList.length;

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

  return (
    <SafeAreaView style={styles.container} edges={["top", "bottom"]}>
      {/* Progress bar */}
      <View style={styles.progressBar}>
        <View style={[styles.progressFill, { width: `${progress * 100}%` }]} />
      </View>

      <View style={styles.content}>
        {/* Word display area */}
        <View style={styles.wordArea}>
          <View style={styles.progressRow}>
            <Text style={styles.progressText}>
              {playback.currentIndex + 1}
              {wrongWords.length > 0
                ? ` / ${wrongWords.length}`
                : ""}{" "}
              / {playback.wordList.length}
            </Text>

            <TouchableOpacity
              style={[
                styles.toggleWordBtn,
                showWord && styles.toggleWordBtnActive,
              ]}
              onPress={() => setShowWord((v) => !v)}
              activeOpacity={0.7}
            >
              <Text
                style={[
                  styles.toggleWordText,
                  showWord && styles.toggleWordTextActive,
                ]}
              >
                {showWord ? "👁 显示中" : "🙈 已隐藏"}
              </Text>
            </TouchableOpacity>
          </View>

          <View
            style={[
              styles.wordCard,
              markedFlash && styles.wordCardFlash,
            ]}
          >
            <Text style={styles.wordText}>
              {showWord && playback.currentIndex < playback.wordList.length
                ? playback.wordList[playback.currentIndex]!
                : "•••••"}
            </Text>
          </View>
        </View>

        {/* Countdown bar (when auto-next is active) */}
        {isActive && autoNext && playback.remainingMs !== null ? (
          <View style={styles.countdownSection}>
            <View style={styles.countdownBar}>
              <View
                style={[
                  styles.countdownFill,
                  { width: `${countdownScale * 100}%` },
                ]}
              />
            </View>
            <Text style={styles.countdownText}>{countdownLabel}</Text>
          </View>
        ) : null}

        {/* Play state indicator */}
        <View style={styles.stateIndicator}>
          <View
            style={[
              styles.stateDot,
              playback.playState === "playing" && styles.stateDotPlaying,
              playback.playState === "paused" && styles.stateDotPaused,
            ]}
          />
          <Text style={styles.stateText}>
            {playback.playState === "playing"
              ? "播放中"
              : playback.playState === "paused"
                ? "已暂停"
                : "已结束"}
          </Text>
        </View>

        {/* Controls */}
        <View style={styles.controls}>
          <View style={styles.controlRow}>
            <TouchableOpacity
              style={[
                styles.controlBtn,
                styles.controlBtnPrimary,
              ]}
              onPress={handlePlayToggle}
              activeOpacity={0.7}
            >
              <Text style={styles.controlBtnText}>
                {playback.playState === "playing" ? "⏸ 暂停" : "▶ 继续"}
              </Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.controlBtn, !skipEnabled && styles.controlBtnDisabled]}
              onPress={playback.skipToNextWord}
              disabled={!skipEnabled}
              activeOpacity={0.7}
            >
              <Text style={styles.controlBtnTextOutline}>⏭ 跳过</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.controlBtn, styles.controlBtnDanger, !isActive && styles.controlBtnDisabled]}
              onPress={handleStop}
              disabled={!isActive}
              activeOpacity={0.7}
            >
              <Text style={styles.controlBtnTextDanger}>⏹ 结束</Text>
            </TouchableOpacity>
          </View>

          <TouchableOpacity
            style={[
              styles.markBtn,
              !markEnabled && styles.controlBtnDisabled,
            ]}
            onPress={handleMarkWrong}
            disabled={!markEnabled}
            activeOpacity={0.7}
          >
            <Text style={styles.markBtnText}>✕ 标记错词</Text>
          </TouchableOpacity>
        </View>

        {/* Wrong words */}
        <View style={styles.wrongSection}>
          <View style={styles.wrongHeader}>
            <Text style={styles.wrongTitle}>错词本 ({wrongWords.length})</Text>
            <View style={styles.wrongActions}>
              <TouchableOpacity style={styles.smallBtn} onPress={handleExport}>
                <Text style={styles.smallBtnText}>导出</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.smallBtn} onPress={handleClearWrong}>
                <Text style={styles.smallBtnText}>清空</Text>
              </TouchableOpacity>
            </View>
          </View>
          {wrongWords.length === 0 ? (
            <Text style={styles.emptyWrong}>尚无错词</Text>
          ) : (
            <View style={styles.chipRow}>
              {wrongWords.map((word) => (
                <TouchableOpacity
                  key={word}
                  style={styles.chip}
                  onPress={() => removeWrongWord(word)}
                  activeOpacity={0.7}
                >
                  <Text style={styles.chipText}>{word}</Text>
                  <Text style={styles.chipRemove}> ×</Text>
                </TouchableOpacity>
              ))}
            </View>
          )}
        </View>
      </View>

      {/* Toast */}
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
    backgroundColor: "#f8f9fa",
  },
  progressBar: {
    height: 4,
    backgroundColor: "#e2e2e2",
  },
  progressFill: {
    height: "100%",
    backgroundColor: "#4a6cf7",
  },
  content: {
    flex: 1,
    padding: 20,
    gap: 20,
  },

  // Word area
  wordArea: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    gap: 16,
  },
  progressRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    alignSelf: "stretch",
  },
  progressText: {
    fontSize: 16,
    color: "#999",
    fontWeight: "500",
  },
  toggleWordBtn: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: "#e2e2e2",
    backgroundColor: "#fff",
  },
  toggleWordBtnActive: {
    backgroundColor: "#eef2ff",
    borderColor: "#4a6cf7",
  },
  toggleWordText: {
    fontSize: 13,
    fontWeight: "500",
    color: "#999",
  },
  toggleWordTextActive: {
    color: "#4a6cf7",
    fontWeight: "600",
  },
  wordCard: {
    backgroundColor: "#fff",
    borderRadius: 16,
    paddingHorizontal: 40,
    paddingVertical: 32,
    minWidth: 200,
    alignItems: "center",
    shadowColor: "#000",
    shadowOpacity: 0.06,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 3,
  },
  wordCardFlash: {
    backgroundColor: "#fff0f0",
    borderWidth: 2,
    borderColor: "#e74c3c",
  },
  wordText: {
    fontSize: 36,
    fontWeight: "700",
    color: "#1a1a2e",
    letterSpacing: 2,
  },
  controlBtnTextDanger: {
    fontSize: 15,
    fontWeight: "600",
    color: "#e74c3c",
  },

  // Countdown
  countdownSection: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
  },
  countdownBar: {
    flex: 1,
    height: 8,
    backgroundColor: "#e2e2e2",
    borderRadius: 4,
    overflow: "hidden",
  },
  countdownFill: {
    height: "100%",
    backgroundColor: "#4a6cf7",
    borderRadius: 4,
  },
  countdownText: {
    fontSize: 14,
    fontWeight: "700",
    color: "#4a6cf7",
    minWidth: 36,
    textAlign: "right",
  },

  // State indicator
  stateIndicator: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
  },
  stateDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: "#ddd",
  },
  stateDotPlaying: {
    backgroundColor: "#27ae60",
  },
  stateDotPaused: {
    backgroundColor: "#f39c12",
  },
  stateText: {
    fontSize: 13,
    color: "#999",
  },

  // Controls
  controls: {
    gap: 10,
  },
  controlRow: {
    flexDirection: "row",
    gap: 10,
  },
  controlBtn: {
    flex: 1,
    height: 48,
    borderRadius: 10,
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 1.5,
    borderColor: "#e2e2e2",
    backgroundColor: "#fff",
  },
  controlBtnPrimary: {
    backgroundColor: "#4a6cf7",
    borderColor: "#4a6cf7",
  },
  controlBtnDanger: {
    backgroundColor: "#fff",
    borderColor: "#e74c3c",
  },
  controlBtnDisabled: {
    opacity: 0.4,
  },
  controlBtnText: {
    fontSize: 15,
    fontWeight: "600",
    color: "#fff",
  },
  controlBtnTextOutline: {
    fontSize: 15,
    fontWeight: "600",
    color: "#555",
  },
  markBtn: {
    height: 48,
    backgroundColor: "#fff0f0",
    borderRadius: 10,
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 1.5,
    borderColor: "#fdd",
  },
  markBtnText: {
    fontSize: 15,
    fontWeight: "600",
    color: "#e74c3c",
  },

  // Wrong words
  wrongSection: {
    maxHeight: 140,
    gap: 10,
  },
  wrongHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  wrongTitle: {
    fontSize: 14,
    fontWeight: "600",
    color: "#888",
  },
  wrongActions: {
    flexDirection: "row",
    gap: 8,
  },
  smallBtn: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 6,
    backgroundColor: "#f0f0f0",
  },
  smallBtnText: {
    fontSize: 12,
    color: "#666",
  },
  emptyWrong: {
    textAlign: "center",
    color: "#bbb",
    fontSize: 13,
    paddingVertical: 12,
    backgroundColor: "#f0f0f0",
    borderRadius: 10,
  },
  chipRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 6,
  },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#e8e8e8",
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
  },
  chipText: {
    fontSize: 13,
    color: "#333",
  },
  chipRemove: {
    fontSize: 14,
    color: "#bbb",
    marginLeft: 2,
  },

  // Toast
  toast: {
    position: "absolute",
    bottom: 40,
    left: 20,
    right: 20,
    backgroundColor: "rgba(0,0,0,0.8)",
    paddingVertical: 12,
    borderRadius: 10,
    alignItems: "center",
  },
  toastText: {
    color: "#fff",
    fontSize: 14,
  },
});
