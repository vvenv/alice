import { useEffect, useRef } from "react";
import {
  Animated,
  Platform,
  Pressable,
  StyleSheet,
  Text,
} from "react-native";

import type { ToastState } from "../hooks/useToast";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

// react-native-web silently drops native-driver animations; fall back to JS there.
const USE_NATIVE_DRIVER = Platform.OS !== "web";

interface ToastProps {
  toast: ToastState;
  /** Called when the action button is pressed (dismisses the toast). */
  onActionPress?: () => void;
}

export function Toast({ toast, onActionPress }: ToastProps) {
  const colors = useThemeColors();
  const anim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (!toast) return;
    anim.setValue(0);
    Animated.spring(anim, {
      toValue: 1,
      friction: 8,
      tension: 80,
      useNativeDriver: USE_NATIVE_DRIVER,
    }).start();
  }, [toast, anim]);

  if (!toast) return null;

  return (
    <Animated.View
      style={[
        styles.wrapper,
        {
          opacity: anim,
          transform: [
            {
              translateY: anim.interpolate({
                inputRange: [0, 1],
                outputRange: [16, 0],
              }),
            },
          ],
        },
      ]}
      pointerEvents="box-none"
    >
      <Animated.View
        style={[
          styles.pill,
          {
            backgroundColor: colors.foreground,
            shadowColor: "#000",
          },
        ]}
      >
        <Text style={[styles.text, { color: colors.background }]}>
          {toast.message}
        </Text>
        {toast.action ? (
          <Pressable
            onPress={() => {
              toast.action?.onPress();
              onActionPress?.();
            }}
            hitSlop={10}
            accessibilityRole="button"
            accessibilityLabel={toast.action.label}
          >
            <Text style={[styles.actionText, { color: colors.gold }]}>
              {toast.action.label}
            </Text>
          </Pressable>
        ) : null}
      </Animated.View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    position: "absolute",
    bottom: 40,
    left: 0,
    right: 0,
    alignItems: "center",
    zIndex: 50,
  },
  pill: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingVertical: 10,
    borderRadius: radii.full,
    shadowOpacity: 0.4,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 8,
  },
  text: {
    fontSize: 14,
    fontWeight: "500",
  },
  actionText: {
    fontSize: 14,
    fontWeight: "700",
  },
});
