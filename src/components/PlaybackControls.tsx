import { Ionicons } from "@expo/vector-icons";
import {
  StyleSheet,
  Switch,
  Text,
  TouchableOpacity,
  View,
} from "react-native";

import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";
import { Slider } from "./Slider";

interface PlaybackControlsProps {
  intervalSec: number;
  autoNext: boolean;
  onIntervalChange: (sec: number) => void;
  onAutoNextChange: (auto: boolean) => void;
  onPlayToggle?: () => void;
  showPlayButton?: boolean;
}

export function PlaybackControls({
  intervalSec,
  autoNext,
  onIntervalChange,
  onAutoNextChange,
  onPlayToggle,
  showPlayButton = true,
}: PlaybackControlsProps) {
  const colors = useThemeColors();

  return (
    <View style={styles.container}>
      <View style={styles.intervalRow}>
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
      </View>

      <View style={styles.autoRow}>
        <Text style={[styles.autoLabel, { color: colors.muted }]}>自动</Text>
        <Switch
          value={autoNext}
          onValueChange={onAutoNextChange}
          trackColor={{ false: colors.track, true: colors.primarySoft }}
          thumbColor={autoNext ? colors.primary : colors.background}
        />
      </View>

      {showPlayButton && onPlayToggle ? (
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
            <View style={styles.mainBtnContent}>
              <Ionicons name="play" size={20} color={colors.background} />
              <Text
                style={[
                  styles.mainBtnTextBase,
                  {
                    color: colors.background,
                  },
                ]}
              >
                开始
              </Text>
            </View>
          </TouchableOpacity>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: spacing.md,
  },
  intervalRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
  },
  label: {
    fontSize: 14,
    flexShrink: 0,
  },
  sliderArea: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
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
    justifyContent: "space-between",
  },
  autoLabel: {
    fontSize: 14,
  },
  buttonRow: {
    flexDirection: "row",
    gap: spacing.md,
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
  mainBtnContent: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.sm,
  },
});
