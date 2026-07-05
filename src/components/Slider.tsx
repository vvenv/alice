import { useCallback, useRef, useState } from "react";
import {
  DimensionValue,
  LayoutChangeEvent,
  PanResponder,
  StyleSheet,
  View,
} from "react-native";

import { useThemeColors } from "../lib/theme";

interface SliderProps {
  min: number;
  max: number;
  step: number;
  value: number;
  onValueChange: (value: number) => void;
  disabled?: boolean;
}

export function Slider({
  min,
  max,
  step,
  value,
  onValueChange,
  disabled,
}: SliderProps) {
  const colors = useThemeColors();
  const containerWidth = useRef(0);
  const fraction = (value - min) / (max - min);
  const fillPct: DimensionValue = `${fraction * 100}%`;
  const thumbLeft = THUMB_SIZE / 2 + fraction * (containerWidth.current - THUMB_SIZE);

  const snapValue = useCallback(
    (pct: number) => {
      const clamped = Math.max(0, Math.min(1, pct));
      let raw = min + clamped * (max - min);
      raw = Math.round(raw / step) * step;
      return Math.max(min, Math.min(max, raw));
    },
    [min, max, step],
  );

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => !disabled,
      onMoveShouldSetPanResponder: () => !disabled,
      onPanResponderGrant: (evt) => {
        const x = evt.nativeEvent.locationX;
        const pct = (x - THUMB_SIZE / 2) / (containerWidth.current - THUMB_SIZE);
        onValueChange(snapValue(pct));
      },
      onPanResponderMove: (evt) => {
        const x = evt.nativeEvent.locationX;
        const pct = (x - THUMB_SIZE / 2) / (containerWidth.current - THUMB_SIZE);
        onValueChange(snapValue(pct));
      },
    }),
  ).current;

  // Thumb position recalculation hack to force re-render with layout
  const [, setLayoutReady] = useState(false);
  const onLayout = useCallback((e: LayoutChangeEvent) => {
    containerWidth.current = e.nativeEvent.layout.width;
    setLayoutReady(true);
  }, []);

  return (
    <View
      style={[styles.container, disabled && styles.disabled]}
      onLayout={onLayout}
      {...panResponder.panHandlers}
    >
      <View
        style={[styles.track, { backgroundColor: colors.border }]}
      >
        <View
          style={[
            styles.fill,
            {
              width: fillPct,
              backgroundColor: colors.primary,
            },
          ]}
        />
      </View>
      <View
        style={[
          styles.thumb,
          {
            left: thumbLeft,
            backgroundColor: colors.primary,
            shadowColor: colors.primary,
          },
        ]}
      />
    </View>
  );
}

const THUMB_SIZE = 24;
const TRACK_HEIGHT = 6;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    height: 40,
    justifyContent: "center",
    paddingHorizontal: THUMB_SIZE / 2,
  },
  disabled: {
    opacity: 0.5,
  },
  track: {
    height: TRACK_HEIGHT,
    borderRadius: TRACK_HEIGHT / 2,
    overflow: "hidden",
  },
  fill: {
    height: "100%",
    borderRadius: TRACK_HEIGHT / 2,
  },
  thumb: {
    position: "absolute",
    top: (40 - THUMB_SIZE) / 2,
    width: THUMB_SIZE,
    height: THUMB_SIZE,
    borderRadius: THUMB_SIZE / 2,
    marginLeft: -THUMB_SIZE / 2,
    shadowOpacity: 0.35,
    shadowRadius: 4,
    shadowOffset: { width: 0, height: 2 },
    elevation: 4,
  },
});
