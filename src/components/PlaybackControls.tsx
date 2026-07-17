import { Ionicons } from "@expo/vector-icons";
import { StyleSheet, Switch, Text, View } from "react-native";

import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";
import { Button } from "./Button";
import { Slider } from "./Slider";

// Ink on gold reads well on both themes' gold accents.
const MEDALLION_INK = "#1A2B4A";

interface PlaybackControlsProps {
  intervalSec: number;
  autoNext: boolean;
  onIntervalChange: (sec: number) => void;
  onAutoNextChange: (auto: boolean) => void;
  onPlayToggle?: () => void;
  showPlayButton?: boolean;
  shuffle?: boolean;
  onShuffleChange?: (shuffle: boolean) => void;
  /** When provided, shows a count badge in the play button and dims it at 0. */
  wordCount?: number;
}

export function PlaybackControls({
  intervalSec,
  autoNext,
  onIntervalChange,
  onAutoNextChange,
  onPlayToggle,
  showPlayButton = true,
  shuffle,
  onShuffleChange,
  wordCount,
}: PlaybackControlsProps) {
  const colors = useThemeColors();
  // Keep the button pressable at 0 so the toast can explain why nothing starts.
  const playLooksDisabled = wordCount === 0;

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

      <View style={styles.toggleRow}>
        <View style={styles.toggleItem}>
          <Text style={[styles.toggleLabel, { color: colors.muted }]}>
            自动
          </Text>
          <Switch
            value={autoNext}
            onValueChange={onAutoNextChange}
            accessibilityLabel="自动播放下一词"
            accessibilityRole="switch"
            accessibilityState={{ checked: autoNext }}
            trackColor={{ false: colors.track, true: colors.primarySoft }}
            thumbColor={autoNext ? colors.primary : colors.background}
          />
        </View>
        {onShuffleChange !== undefined && (
          <View style={styles.toggleItem}>
            <Text style={[styles.toggleLabel, { color: colors.muted }]}>
              随机
            </Text>
            <Switch
              value={shuffle}
              onValueChange={onShuffleChange}
              accessibilityLabel="随机顺序"
              accessibilityRole="switch"
              accessibilityState={{ checked: Boolean(shuffle) }}
              trackColor={{ false: colors.track, true: colors.primarySoft }}
              thumbColor={shuffle ? colors.primary : colors.background}
            />
          </View>
        )}
      </View>

      {showPlayButton && onPlayToggle ? (
        <Button
          label="开始听写"
          leading={
            <View
              style={[styles.playMedallion, { backgroundColor: colors.gold }]}
            >
              <Ionicons name="play" size={14} color={MEDALLION_INK} />
            </View>
          }
          variant="primary"
          size="lg"
          onPress={onPlayToggle}
          dimmed={playLooksDisabled}
        >
          {wordCount ? (
            <View
              style={[
                styles.mainBtnBadge,
                { backgroundColor: `${colors.background}2E` },
              ]}
            >
              <Text
                style={[styles.mainBtnBadgeText, { color: colors.background }]}
              >
                {wordCount} 词
              </Text>
            </View>
          ) : null}
        </Button>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: spacing.sm,
  },
  intervalRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
  },
  label: {
    fontSize: 13,
    flexShrink: 0,
  },
  sliderArea: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
  },
  countValue: {
    fontSize: 13,
    fontWeight: "600",
    minWidth: 36,
    textAlign: "right",
    fontVariant: ["tabular-nums"],
  },
  toggleRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  toggleItem: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: spacing.lg,
  },
  toggleLabel: {
    fontSize: 13,
  },
  playMedallion: {
    width: 26,
    height: 26,
    borderRadius: radii.full,
    alignItems: "center",
    justifyContent: "center",
    paddingLeft: 2,
  },
  mainBtnBadge: {
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: radii.full,
  },
  mainBtnBadgeText: {
    fontSize: 12,
    fontWeight: "700",
    fontVariant: ["tabular-nums"],
  },
});
