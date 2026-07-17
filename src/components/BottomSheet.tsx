/**
 * Shared bottom sheet chrome: dimmed backdrop, rounded panel with a grab
 * handle, spring entrance. All bottom-anchored modals (menu, drawers, action
 * sheets) go through this so they feel like one product.
 */
import { useEffect, useRef, type ReactNode } from "react";
import {
  Animated,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { fonts, radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

// react-native-web silently drops native-driver animations; fall back to JS there.
const USE_NATIVE_DRIVER = Platform.OS !== "web";

interface BottomSheetProps {
  visible: boolean;
  onClose: () => void;
  title?: string;
  headerRight?: ReactNode;
  /** Fraction of the window height the sheet may grow to. */
  maxHeightRatio?: number;
  /**
   * Sheet content. Function children receive the max height available for a
   * scrollable body (sheet max height minus chrome), for capped ScrollViews.
   */
  children: ReactNode | ((bodyMaxHeight: number) => ReactNode);
}

export function BottomSheet({
  visible,
  onClose,
  title,
  headerRight,
  maxHeightRatio = 0.8,
  children,
}: BottomSheetProps) {
  const colors = useThemeColors();
  const insets = useSafeAreaInsets();
  const { height } = useWindowDimensions();

  const sheetMaxHeight = height * maxHeightRatio;
  const bottomPad = Math.max(insets.bottom, spacing.xl);
  const chromeHeight =
    spacing.lg + // paddingTop
    4 +
    spacing.md + // handle
    (title ? 28 + spacing.sm : 0) + // header
    bottomPad;
  const bodyMaxHeight = Math.max(160, sheetMaxHeight - chromeHeight);

  // Modal slide animates the whole tree (backdrop included). Keep Modal static
  // and animate backdrop + panel separately.
  const translateY = useRef(new Animated.Value(sheetMaxHeight)).current;
  const backdropOpacity = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (!visible) {
      translateY.setValue(sheetMaxHeight);
      backdropOpacity.setValue(0);
      return;
    }
    translateY.setValue(sheetMaxHeight);
    backdropOpacity.setValue(0);
    Animated.parallel([
      Animated.timing(backdropOpacity, {
        toValue: 1,
        duration: 180,
        useNativeDriver: USE_NATIVE_DRIVER,
      }),
      Animated.spring(translateY, {
        toValue: 0,
        friction: 10,
        tension: 70,
        useNativeDriver: USE_NATIVE_DRIVER,
      }),
    ]).start();
  }, [visible, sheetMaxHeight, translateY, backdropOpacity]);

  return (
    <Modal
      visible={visible}
      transparent
      animationType="none"
      onRequestClose={onClose}
      statusBarTranslucent={Platform.OS === "android"}
      presentationStyle="overFullScreen"
    >
      <View style={styles.root}>
        <Animated.View
          style={[
            StyleSheet.absoluteFill,
            { backgroundColor: colors.overlay, opacity: backdropOpacity },
          ]}
        >
          <Pressable style={StyleSheet.absoluteFill} onPress={onClose} />
        </Animated.View>
        <Animated.View
          style={[
            styles.sheet,
            {
              backgroundColor: colors.background,
              borderColor: colors.borderSubtle,
              maxHeight: sheetMaxHeight,
              paddingBottom: bottomPad,
              transform: [{ translateY }],
            },
          ]}
        >
          <View style={[styles.handle, { backgroundColor: colors.border }]} />
          {title ? (
            <View style={styles.header}>
              <Text style={[styles.title, { color: colors.foreground }]}>
                {title}
              </Text>
              {headerRight}
            </View>
          ) : null}
          {typeof children === "function" ? children(bodyMaxHeight) : children}
        </Animated.View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    justifyContent: "flex-end",
  },
  sheet: {
    width: "100%",
    maxWidth: 640,
    alignSelf: "center",
    borderTopLeftRadius: radii.shell,
    borderTopRightRadius: radii.shell,
    borderWidth: 1,
    borderBottomWidth: 0,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
  },
  handle: {
    width: 36,
    height: 4,
    borderRadius: radii.full,
    alignSelf: "center",
    marginBottom: spacing.md,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: spacing.sm,
  },
  title: {
    fontFamily: fonts.displayZh,
    fontSize: 17,
    fontWeight: "700",
  },
});
