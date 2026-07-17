/**
 * Shared button primitives. All tappable "button-like" surfaces should go
 * through <Button> / <IconButton> so press feedback (spring scale + haptic),
 * disabled states, and accessibility come for free and stay consistent.
 */
import { Ionicons } from "@expo/vector-icons";
import { useRef, type ReactNode } from "react";
import {
  Animated,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  type StyleProp,
  type ViewStyle,
} from "react-native";

import { fonts, radii, spacing } from "../lib/designTokens";
import { tapLight } from "../lib/haptics";
import { useThemeColors } from "../lib/theme";

export type ButtonVariant = "primary" | "outline" | "danger" | "ghost";
export type ButtonSize = "lg" | "md" | "sm";

interface ButtonProps {
  label: string;
  onPress?: () => void;
  variant?: ButtonVariant;
  size?: ButtonSize;
  icon?: keyof typeof Ionicons.glyphMap;
  /** Custom node rendered before the label (replaces icon when set). */
  leading?: ReactNode;
  /** Selected/toggled-on look (outline variant only). */
  active?: boolean;
  /** Blocks presses and dims the button. */
  disabled?: boolean;
  /** Looks disabled but stays pressable, so onPress can explain why. */
  dimmed?: boolean;
  haptic?: boolean;
  style?: StyleProp<ViewStyle>;
  accessibilityLabel?: string;
  /** Extra content rendered after the label (e.g. a count badge). */
  children?: ReactNode;
}

const SIZE_SPECS = {
  lg: {
    minHeight: 52,
    borderRadius: radii.button,
    paddingHorizontal: spacing.xl,
    fontSize: 17,
    iconSize: 20,
    gap: spacing.sm,
  },
  md: {
    minHeight: 48,
    borderRadius: radii.control,
    paddingHorizontal: spacing.lg,
    fontSize: 14,
    iconSize: 16,
    gap: spacing.xs,
  },
  sm: {
    minHeight: 30,
    borderRadius: radii.full,
    paddingHorizontal: spacing.md,
    fontSize: 12,
    iconSize: 14,
    gap: spacing.xs,
  },
} as const;

// react-native-web silently drops native-driver animations; fall back to JS there.
const USE_NATIVE_DRIVER = Platform.OS !== "web";

function usePressScale() {
  const scale = useRef(new Animated.Value(1)).current;
  const pressIn = () => {
    Animated.spring(scale, {
      toValue: 0.96,
      useNativeDriver: USE_NATIVE_DRIVER,
      speed: 40,
      bounciness: 0,
    }).start();
  };
  const pressOut = () => {
    Animated.spring(scale, {
      toValue: 1,
      useNativeDriver: USE_NATIVE_DRIVER,
      speed: 30,
      bounciness: 6,
    }).start();
  };
  return { scale, pressIn, pressOut };
}

export function Button({
  label,
  onPress,
  variant = "outline",
  size = "md",
  icon,
  leading,
  active = false,
  disabled = false,
  dimmed = false,
  haptic = true,
  style,
  accessibilityLabel,
  children,
}: ButtonProps) {
  const colors = useThemeColors();
  const { scale, pressIn, pressOut } = usePressScale();
  const spec = SIZE_SPECS[size];

  const palette = {
    primary: {
      bg: colors.primary,
      border: "transparent",
      text: colors.background,
    },
    outline: active
      ? { bg: colors.primarySoft, border: colors.primary, text: colors.primary }
      : {
          bg: colors.background,
          border: colors.border,
          text: colors.secondary,
        },
    danger: {
      bg: colors.background,
      border: colors.dangerMuted,
      text: colors.danger,
    },
    ghost: {
      bg: colors.surface,
      border: "transparent",
      text: colors.secondary,
    },
  }[variant];

  const hasBorder = variant === "outline" || variant === "danger";
  const inactiveLook = disabled || dimmed;
  const showShadow = variant === "primary" && size === "lg" && !inactiveLook;

  return (
    <Animated.View style={[{ transform: [{ scale }] }, style]}>
      <Pressable
        onPress={onPress}
        onPressIn={() => {
          if (haptic) tapLight();
          pressIn();
        }}
        onPressOut={pressOut}
        disabled={disabled}
        hitSlop={size === "sm" ? 8 : undefined}
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel ?? label}
        accessibilityState={disabled ? { disabled: true } : undefined}
        style={[
          styles.base,
          {
            minHeight: spec.minHeight,
            paddingVertical: size === "sm" ? spacing.xs : spacing.sm,
            borderRadius: spec.borderRadius,
            paddingHorizontal: spec.paddingHorizontal,
            gap: spec.gap,
            backgroundColor: palette.bg,
            borderColor: palette.border,
            borderWidth: hasBorder ? (size === "sm" ? 1 : 1.5) : 0,
          },
          showShadow && {
            shadowColor: colors.primary,
            shadowOpacity: 0.35,
            shadowRadius: 8,
            shadowOffset: { width: 0, height: 4 },
            elevation: 4,
          },
          inactiveLook && styles.inactive,
        ]}
      >
        {leading ??
          (icon ? (
            <Ionicons name={icon} size={spec.iconSize} color={palette.text} />
          ) : null)}
        <Text
          style={[
            styles.label,
            { fontSize: spec.fontSize, color: palette.text },
            size === "lg" && styles.labelDisplay,
          ]}
        >
          {label}
        </Text>
        {children}
      </Pressable>
    </Animated.View>
  );
}

type IconButtonVariant = "surface" | "primary" | "danger" | "gold";

// Ink reads well on both themes' golds.
const GOLD_INK = "#1A2B4A";

interface IconButtonProps {
  icon: keyof typeof Ionicons.glyphMap;
  accessibilityLabel: string;
  onPress?: () => void;
  size?: number;
  variant?: IconButtonVariant;
  disabled?: boolean;
  haptic?: boolean;
  style?: StyleProp<ViewStyle>;
}

/** Circular icon-only button (headers, card corners, player controls). */
export function IconButton({
  icon,
  accessibilityLabel,
  onPress,
  size = 36,
  variant = "surface",
  disabled = false,
  haptic = true,
  style,
}: IconButtonProps) {
  const colors = useThemeColors();
  const { scale, pressIn, pressOut } = usePressScale();

  const palette = {
    surface: {
      bg: colors.surface,
      border: colors.border,
      icon: colors.foreground,
    },
    primary: {
      bg: colors.primary,
      border: "transparent",
      icon: colors.background,
    },
    danger: {
      bg: colors.background,
      border: colors.dangerMuted,
      icon: colors.danger,
    },
    gold: {
      bg: colors.gold,
      border: "transparent",
      icon: GOLD_INK,
    },
  }[variant];

  const isFilled = variant === "primary" || variant === "gold";

  return (
    <Animated.View style={[{ transform: [{ scale }] }, style]}>
      <Pressable
        onPress={onPress}
        onPressIn={() => {
          if (haptic) tapLight();
          pressIn();
        }}
        onPressOut={pressOut}
        disabled={disabled}
        hitSlop={8}
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        accessibilityState={disabled ? { disabled: true } : undefined}
        style={[
          styles.iconBtn,
          {
            width: size,
            height: size,
            borderRadius: radii.full,
            backgroundColor: palette.bg,
            borderColor: palette.border,
            borderWidth: isFilled ? 0 : 1,
          },
          isFilled && {
            shadowColor: variant === "gold" ? colors.gold : colors.primary,
            shadowOpacity: 0.35,
            shadowRadius: 8,
            shadowOffset: { width: 0, height: 4 },
            elevation: 4,
          },
          disabled && styles.inactive,
        ]}
      >
        <Ionicons name={icon} size={size / 2} color={palette.icon} />
      </Pressable>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  base: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
  },
  label: {
    fontWeight: "600",
    flexShrink: 1,
    textAlign: "center",
  },
  labelDisplay: {
    fontFamily: fonts.displayZh,
    fontWeight: "700",
    letterSpacing: 0.5,
  },
  inactive: {
    opacity: 0.45,
  },
  iconBtn: {
    borderWidth: 1,
    justifyContent: "center",
    alignItems: "center",
  },
});
