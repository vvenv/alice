import { StyleSheet, Switch, Text, TouchableOpacity, View } from "react-native";

import { SYSTEM_TTS_VOICES } from "../lib/dictation";
import { colors, radii, spacing } from "../lib/designTokens";

type PlayState = "idle" | "playing" | "paused";

interface PlaybackControlsProps {
  playState: PlayState;
  intervalSec: number;
  autoNext: boolean;
  voice: string;
  remainingMs: number | null;
  currentIndex: number;
  wordList: string[];
  onIntervalChange: (sec: number) => void;
  onAutoNextChange: (auto: boolean) => void;
  onVoiceChange: (voice: string) => void;
  onPlayToggle: () => void;
  onStop: () => void;
  onSkipNext: () => void;
  onMarkWrong: () => void;
}

export function PlaybackControls({
  playState,
  intervalSec,
  autoNext,
  voice,
  remainingMs,
  currentIndex,
  wordList,
  onIntervalChange,
  onAutoNextChange,
  onVoiceChange,
  onPlayToggle,
  onStop,
  onSkipNext,
  onMarkWrong,
}: PlaybackControlsProps) {
  const isActive = playState === "playing" || playState === "paused";
  const markEnabled = isActive && currentIndex < wordList.length;
  const skipEnabled = isActive && currentIndex < wordList.length;
  const intervalMs = intervalSec * 1000;
  const countdownScale =
    remainingMs !== null && intervalMs > 0 ? remainingMs / intervalMs : 0;
  const countdownLabel =
    remainingMs !== null ? `${Math.ceil(remainingMs / 1000)}s` : "—";

  return (
    <View style={styles.container}>
      {/* Voice selector — only when idle */}
      {!isActive && (
        <View style={styles.row}>
          <Text style={styles.label}>音色</Text>
          <View style={styles.segment}>
            {SYSTEM_TTS_VOICES.map((item) => {
              const active = voice === item.id;
              return (
                <TouchableOpacity
                  key={item.id}
                  style={[styles.segmentItem, active && styles.segmentItemActive]}
                  onPress={() => onVoiceChange(item.id)}
                  activeOpacity={0.6}
                >
                  <Text
                    style={[
                      styles.segmentText,
                      active && styles.segmentTextActive,
                    ]}
                  >
                    {item.label}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>
        </View>
      )}

      {/* Interval / Countdown */}
      <View style={styles.row}>
        <Text style={styles.label}>{isActive ? "下一词" : "间隔"}</Text>
        <View style={styles.sliderArea}>
          {isActive ? (
            <View style={styles.countdownBar}>
              <View
                style={[
                  styles.countdownFill,
                  { width: `${countdownScale * 100}%` },
                ]}
              />
            </View>
          ) : (
            <View style={styles.sliderPresets}>
              {[1, 2, 4, 6, 8, 10].map((v) => (
                <TouchableOpacity
                  key={v}
                  style={[
                    styles.presetBtn,
                    intervalSec === v && styles.presetBtnActive,
                  ]}
                  onPress={() => onIntervalChange(v)}
                  activeOpacity={0.6}
                >
                  <Text
                    style={[
                      styles.presetBtnText,
                      intervalSec === v && styles.presetBtnTextActive,
                    ]}
                  >
                    {v}s
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          )}
          <Text style={styles.countValue}>
            {isActive ? countdownLabel : `${intervalSec.toFixed(1)}s`}
          </Text>
        </View>
        {!isActive && (
          <View style={styles.autoRow}>
            <Text style={styles.autoLabel}>自动</Text>
            <Switch
              value={autoNext}
              onValueChange={onAutoNextChange}
              trackColor={{ false: colors.track, true: colors.primaryRing }}
              thumbColor={autoNext ? colors.primary : colors.background}
            />
          </View>
        )}
      </View>

      {/* Play / Skip / Stop */}
      <View style={styles.buttonRow}>
        <TouchableOpacity
          style={[
            styles.mainBtn,
            playState === "playing"
              ? styles.mainBtnPause
              : styles.mainBtnPlay,
          ]}
          onPress={onPlayToggle}
          activeOpacity={0.7}
        >
          <Text
            style={[
              styles.mainBtnTextBase,
              playState === "playing"
                ? styles.mainBtnTextPause
                : styles.mainBtnTextPlay,
            ]}
          >
            {playState === "idle" && "▶ 开始"}
            {playState === "playing" && "⏸ 暂停"}
            {playState === "paused" && "▶ 继续"}
          </Text>
        </TouchableOpacity>
        {isActive && (
          <TouchableOpacity
            style={[styles.secondaryBtn, !skipEnabled && styles.btnDisabled]}
            disabled={!skipEnabled}
            onPress={onSkipNext}
            activeOpacity={0.7}
          >
            <Text style={styles.secondaryBtnText}>⏭ 跳过</Text>
          </TouchableOpacity>
        )}
        <TouchableOpacity
          style={[styles.secondaryBtn, !isActive && styles.btnDisabled]}
          disabled={!isActive}
          onPress={onStop}
          activeOpacity={0.7}
        >
          <Text style={styles.secondaryBtnText}>⏹ 结束</Text>
        </TouchableOpacity>
      </View>

      {/* Mark wrong */}
      <TouchableOpacity
        style={[styles.markBtn, !markEnabled && styles.markBtnDisabled]}
        disabled={!markEnabled}
        onPress={onMarkWrong}
        activeOpacity={0.7}
      >
        <Text style={styles.markBtnText}>✕ 标记错词</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
  },
  label: {
    fontSize: 14,
    color: colors.muted,
    flexShrink: 0,
  },
  segment: {
    flex: 1,
    flexDirection: "row",
    backgroundColor: colors.surfaceRaised,
    borderRadius: radii.surface,
    padding: 4,
    gap: 6,
  },
  segmentItem: {
    flex: 1,
    alignItems: "center",
    borderRadius: radii.control,
    paddingVertical: 6,
    paddingHorizontal: 4,
  },
  segmentItemActive: {
    backgroundColor: colors.background,
    shadowColor: "#000",
    shadowOpacity: 0.1,
    shadowRadius: 2,
    shadowOffset: { width: 0, height: 1 },
    elevation: 2,
  },
  segmentText: {
    fontSize: 14,
    fontWeight: "500",
    color: colors.muted,
  },
  segmentTextActive: {
    color: colors.foreground,
  },
  sliderArea: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  countdownBar: {
    flex: 1,
    height: 8,
    backgroundColor: colors.border,
    borderRadius: 4,
    overflow: "hidden",
  },
  countdownFill: {
    height: "100%",
    backgroundColor: colors.primary,
    borderRadius: 4,
  },
  sliderPresets: {
    flex: 1,
    flexDirection: "row",
    gap: 4,
  },
  presetBtn: {
    flex: 1,
    alignItems: "center",
    borderRadius: radii.control,
    paddingVertical: 6,
  },
  presetBtnActive: {
    backgroundColor: colors.primarySoft,
  },
  presetBtnText: {
    fontSize: 12,
    fontWeight: "500",
    color: colors.muted,
  },
  presetBtnTextActive: {
    color: colors.primary,
    fontWeight: "600",
  },
  countValue: {
    fontSize: 14,
    fontWeight: "600",
    color: colors.primary,
    minWidth: 36,
    textAlign: "right",
    fontVariant: ["tabular-nums"],
  },
  autoRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  autoLabel: {
    fontSize: 14,
    color: colors.muted,
  },
  buttonRow: {
    flexDirection: "row",
    gap: 10,
  },
  mainBtn: {
    flex: 1,
    minHeight: 52,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
  },
  mainBtnPlay: {
    backgroundColor: colors.primary,
    shadowColor: colors.primary,
    shadowOpacity: 0.35,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
    elevation: 4,
  },
  mainBtnPause: {
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
  },
  mainBtnTextBase: {
    fontSize: 17,
    fontWeight: "600",
  },
  mainBtnTextPlay: {
    color: colors.background,
  },
  mainBtnTextPause: {
    color: colors.foreground,
  },
  secondaryBtn: {
    flex: 1,
    minHeight: 52,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.background,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
  },
  secondaryBtnText: {
    fontSize: 17,
    fontWeight: "600",
    color: colors.secondary,
  },
  btnDisabled: {
    opacity: 0.4,
  },
  markBtn: {
    minHeight: 52,
    backgroundColor: colors.dangerSoft,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 1,
    borderColor: colors.dangerHover,
  },
  markBtnDisabled: {
    opacity: 0.3,
  },
  markBtnText: {
    fontSize: 17,
    fontWeight: "600",
    color: colors.danger,
  },
});
