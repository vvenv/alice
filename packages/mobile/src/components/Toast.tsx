import { Animated, StyleSheet, Text } from "react-native";

import { colors, radii } from "../lib/designTokens";

interface ToastProps {
  message: string;
}

export function Toast({ message }: ToastProps) {
  if (!message) return null;

  return (
    <Animated.View style={styles.wrapper}>
      <Text style={styles.text}>{message}</Text>
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
    backgroundColor: colors.foreground,
    color: colors.background,
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
