import {
  StyleSheet,
  Switch,
  Text,
  TouchableOpacity,
  View,
  ViewStyle,
} from "react-native";

import { SYSTEM_TTS_VOICES } from "../lib/dictation";
import { radii } from "../lib/designTokens";
import { useThemeColors, type ThemeColors } from "../lib/theme";
import { Slider } from "./Slider";

interface PlaybackControlsProps {
  intervalSec: number;
  autoNext: boolean;
  voice: string;
  onIntervalChange: (sec: number) => void;
  onAutoNextChange: (auto: boolean) => void;
  onVoiceChange: (voice: string) => void;
  onPlayToggle: () => void;
}

export function PlaybackControls({
  intervalSec,
  autoNext,
  voice,
  onIntervalChange,
  onAutoNextChange,
  onVoiceChange,
  onPlayToggle,
}: PlaybackControlsProps) {
  const colors = useThemeColors();

  return (
    <View style={styles.container}>
      {/* Voice selector — only when idle */}
      <View style={styles.row}>
        <Text style={[styles.label, { color: colors.muted }]}>音色</Text>
        <View
          style={[styles.segment, { backgroundColor: colors.surfaceRaised }]}
        >
          {SYSTEM_TTS_VOICES.map((item) => {
            const active = voice === item.id;
            return (
              <TouchableOpacity
                key={item.id}
                style={[
                  styles.segmentItem,
                  active && {
                    backgroundColor: colors.background,
                    shadowColor: "#000",
                    shadowOpacity: 0.1,
                    shadowRadius: 2,
                    shadowOffset: { width: 0, height: 1 },
                    elevation: 2,
                  },
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

      {/* Interval / Countdown */}
      <View style={styles.row}>
        <Text style={[styles.label, { color: colors.muted }]}>间隔</Text>
        <View style={styles.sliderArea}>
          <Slider
            min={1}
            max={10}
            step={0.5}
            value={intervalSec}
            onValueChange={onIntervalChange}
          />
          <Text style={[styles.countValue, { color: colors.primary }]}>
            {intervalSec.toFixed(1)}s
          </Text>
        </View>
        <View style={styles.autoRow}>
          <Text style={[styles.autoLabel, { color: colors.muted }]}>自动</Text>
          <Switch
            value={autoNext}
            onValueChange={onAutoNextChange}
            trackColor={{ false: colors.track, true: colors.primaryRing }}
            thumbColor={autoNext ? colors.primary : colors.background}
          />
        </View>
      </View>

      {/* Play / Skip / Stop */}
      <View style={styles.buttonRow}>
        <TouchableOpacity
          style={[
            styles.mainBtn,
            {
              backgroundColor: colors.primary,
              shadowColor: colors.primary,
              shadowOpacity: 0.35,
              shadowRadius: 8,
              shadowOffset: { width: 0, height: 4 },
              elevation: 4,
            },
          ]}
          onPress={onPlayToggle}
          activeOpacity={0.7}
        >
          <Text
            style={[
              styles.mainBtnTextBase,
              {
                color: colors.background,
              },
            ]}
          >
            ▶ 开始
          </Text>
        </TouchableOpacity>
      </View>
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
    fontSize: 16,
    fontWeight: "600",
  },
});
