import { StyleSheet, Switch, Text, TouchableOpacity, View } from "react-native";

import { SYSTEM_TTS_VOICES } from "../lib/dictation";
import { radii } from "../lib/designTokens";
import { useThemeColors, type ThemeColors } from "../lib/theme";
import { Slider } from "./Slider";

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
  const colors = useThemeColors();
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
          <Text style={[styles.label, { color: colors.muted }]}>音色</Text>
          <View style={[styles.segment, { backgroundColor: colors.surfaceRaised }]}>
            {SYSTEM_TTS_VOICES.map((item) => {
              const active = voice === item.id;
              return (
                <TouchableOpacity
                  key={item.id}
                  style={[
                    styles.segmentItem,
                    active && { backgroundColor: colors.background, shadowColor: "#000", shadowOpacity: 0.1, shadowRadius: 2, shadowOffset: { width: 0, height: 1 }, elevation: 2 },
                  ]}
                  onPress={() => onVoiceChange(item.id)}
                  activeOpacity={0.6}
                >
                  <Text
                    style={[
                      styles.segmentText,
                      { color: active ? colors.foreground : colors.muted },
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
        <Text style={[styles.label, { color: colors.muted }]}>
          {isActive ? "下一词" : "间隔"}
        </Text>
        <View style={styles.sliderArea}>
          {isActive ? (
            <View style={[styles.countdownBar, { backgroundColor: colors.border }]}>
              <View
                style={[
                  styles.countdownFill,
                  { width: `${countdownScale * 100}%`, backgroundColor: colors.primary },
                ]}
              />
            </View>
          ) : (
            <Slider
              min={1}
              max={10}
              step={0.5}
              value={intervalSec}
              onValueChange={onIntervalChange}
              disabled={isActive}
            />
          )}
          <Text style={[styles.countValue, { color: colors.primary }]}>
            {isActive ? countdownLabel : `${intervalSec.toFixed(1)}s`}
          </Text>
        </View>
        {!isActive && (
          <View style={styles.autoRow}>
            <Text style={[styles.autoLabel, { color: colors.muted }]}>自动</Text>
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
              ? { backgroundColor: colors.background, borderWidth: 1, borderColor: colors.border }
              : { backgroundColor: colors.primary, shadowColor: colors.primary, shadowOpacity: 0.35, shadowRadius: 8, shadowOffset: { width: 0, height: 4 }, elevation: 4 },
          ]}
          onPress={onPlayToggle}
          activeOpacity={0.7}
        >
          <Text
            style={[
              styles.mainBtnTextBase,
              {
                color:
                  playState === "playing" ? colors.foreground : colors.background,
              },
            ]}
          >
            {playState === "idle" && "▶ 开始"}
            {playState === "playing" && "⏸ 暂停"}
            {playState === "paused" && "▶ 继续"}
          </Text>
        </TouchableOpacity>
        {isActive && (
          <TouchableOpacity
            style={[styles.secondaryBtn(colors), !skipEnabled && styles.btnDisabled]}
            disabled={!skipEnabled}
            onPress={onSkipNext}
            activeOpacity={0.7}
          >
            <Text style={[styles.secondaryBtnText, { color: colors.secondary }]}>⏭ 跳过</Text>
          </TouchableOpacity>
        )}
        <TouchableOpacity
          style={[styles.secondaryBtn(colors), !isActive && styles.btnDisabled]}
          disabled={!isActive}
          onPress={onStop}
          activeOpacity={0.7}
        >
          <Text style={[styles.secondaryBtnText, { color: colors.secondary }]}>⏹ 结束</Text>
        </TouchableOpacity>
      </View>

      {/* Mark wrong */}
      <TouchableOpacity
        style={[styles.markBtn(colors), !markEnabled && styles.markBtnDisabled]}
        disabled={!markEnabled}
        onPress={onMarkWrong}
        activeOpacity={0.7}
      >
        <Text style={[styles.markBtnText, { color: colors.danger }]}>✕ 标记错词</Text>
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
    flexShrink: 0,
  },
  segment: {
    flex: 1,
    flexDirection: "row",
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
  segmentText: {
    fontSize: 14,
    fontWeight: "500",
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
    borderRadius: 4,
    overflow: "hidden",
  },
  countdownFill: {
    height: "100%",
    borderRadius: 4,
  },
  countValue: {
    fontSize: 14,
    fontWeight: "600",
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
  mainBtnTextBase: {
    fontSize: 17,
    fontWeight: "600",
  },
  secondaryBtn: (colors: ThemeColors) => ({
    flex: 1,
    minHeight: 52,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.background,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
  }),
  secondaryBtnText: {
    fontSize: 17,
    fontWeight: "600",
  },
  btnDisabled: {
    opacity: 0.4,
  },
  markBtn: (colors: ThemeColors) => ({
    minHeight: 52,
    backgroundColor: colors.dangerSoft,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 1,
    borderColor: colors.dangerHover,
  }),
  markBtnDisabled: {
    opacity: 0.3,
  },
  markBtnText: {
    fontSize: 17,
    fontWeight: "600",
  },
});
