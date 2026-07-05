import { useCallback, useMemo, useRef, useState } from "react";
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

  const containerRef = useRef<View>(null);
  const containerWidth = useRef(0);
  const containerPageX = useRef(0);

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

  // Keep mutable refs for callbacks so PanResponder never uses stale closures
  const snapValueRef = useRef(snapValue);
  snapValueRef.current = snapValue;
  const onValueChangeRef = useRef(onValueChange);
  onValueChangeRef.current = onValueChange;
  const disabledRef = useRef(disabled);
  disabledRef.current = disabled;

  // Use pageX (absolute screen coords) instead of locationX to avoid the
  // Android bug where locationX is measured relative to whichever child view
  // is under the finger, shifting the coordinate system on every re-render.
  const panResponder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => !disabledRef.current,
        onMoveShouldSetPanResponder: () => !disabledRef.current,
        onPanResponderGrant: (evt) => {
          const x = evt.nativeEvent.pageX - containerPageX.current;
          const pct = (x - THUMB_SIZE / 2) / (containerWidth.current - THUMB_SIZE);
          onValueChangeRef.current(snapValueRef.current(pct));
        },
        onPanResponderMove: (evt) => {
          const x = evt.nativeEvent.pageX - containerPageX.current;
          const pct = (x - THUMB_SIZE / 2) / (containerWidth.current - THUMB_SIZE);
          onValueChangeRef.current(snapValueRef.current(pct));
        },
      }),
    [],
  );

  const [, setLayoutReady] = useState(false);
  const onLayout = useCallback((e: LayoutChangeEvent) => {
    containerWidth.current = e.nativeEvent.layout.width;
    // Measure the container's absolute X so we can translate pageX to local coords
    containerRef.current?.measureInWindow((x) => {
      containerPageX.current = x;
    });
    setLayoutReady(true);
  }, []);

  return (
    <View
      ref={containerRef}
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
