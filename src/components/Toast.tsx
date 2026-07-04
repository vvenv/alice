import { Animated, StyleSheet, Text } from "react-native";

import { useThemeColors } from "../lib/theme";
import { radii } from "../lib/designTokens";

interface ToastProps {
  message: string;
}

export function Toast({ message }: ToastProps) {
  const colors = useThemeColors();

  if (!message) return null;

  return (
    <Animated.View style={styles.wrapper}>
      <Text
        style={[
          styles.text,
          {
            backgroundColor: colors.foreground,
            color: colors.background,
          },
        ]}
      >
        {message}
      </Text>
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
  text: {
    fontSize: 14,
    fontWeight: "500",
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: radii.full,
    overflow: "hidden",
    shadowColor: "#000",
    shadowOpacity: 0.4,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 8,
  },
});
