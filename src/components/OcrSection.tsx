import { Ionicons } from "@expo/vector-icons";
import {
  forwardRef,
  useCallback,
  useImperativeHandle,
  useState,
} from "react";
import {
  ActivityIndicator,
  LayoutAnimation,
  Platform,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  UIManager,
  View,
} from "react-native";

// Enable LayoutAnimation on Android
if (
  Platform.OS === "android" &&
  UIManager.setLayoutAnimationEnabledExperimental
) {
  UIManager.setLayoutAnimationEnabledExperimental(true);
}

import { config } from "../lib/config";
import {
  takePhoto,
  pickFromAlbum,
  ocrWordsFromImage,
  OCR_PROGRESS_MESSAGES,
  OCR_OUTCOME_MESSAGES,
  OCR_UI_IDLE,
  type OcrProgressPhase,
  type OcrUiState,
} from "../lib/ocr";
import { useThemeColors } from "../lib/theme";
import { radii, spacing } from "../lib/designTokens";

interface OcrSectionProps {
  ocrUnlocked: boolean;
  onOcrResult: (words: string[]) => void;
  onUnlockOcr: (code: string) => boolean;
  /** When true, hide the inline 拍照/相册 buttons (actions live in header menu). */
  hideActions?: boolean;
  /** In-flight header state: busy + progress message. */
  onOcrStateChange?: (state: OcrUiState) => void;
  /** Terminal outcome for toast (success / empty / error). */
  onOcrOutcome?: (message: string) => void;
}

export type OcrSectionHandle = {
  processPhoto: () => void;
  processAlbum: () => void;
  busy: boolean;
};

const ALPHANUMERIC = /^[a-zA-Z0-9]*$/;

export const OcrSection = forwardRef<OcrSectionHandle, OcrSectionProps>(
  function OcrSection(
    {
      ocrUnlocked,
      onOcrResult,
      onUnlockOcr,
      hideActions = false,
      onOcrStateChange,
      onOcrOutcome,
    },
    ref,
  ) {
    const colors = useThemeColors();
    const [ocrBusy, setOcrBusy] = useState(false);
    const [unlockCode, setUnlockCode] = useState("");
    const [unlockError, setUnlockError] = useState(false);
    const [showUnlock, setShowUnlock] = useState(false);
    const [paywallCollapsed, setPaywallCollapsed] = useState(true);

    const setUiState = useCallback(
      (state: OcrUiState) => {
        setOcrBusy(state.busy);
        onOcrStateChange?.(state);
      },
      [onOcrStateChange],
    );

    const reportProgress = useCallback(
      (phase: OcrProgressPhase) => {
        setUiState({ busy: true, message: OCR_PROGRESS_MESSAGES[phase] });
      },
      [setUiState],
    );

    const togglePaywall = useCallback(() => {
      LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
      setPaywallCollapsed((v) => !v);
    }, []);

    const revealPaywall = useCallback(() => {
      LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
      setShowUnlock(false);
      setPaywallCollapsed(false);
    }, []);

    const runOcr = useCallback(
      async (
        getUri: () => Promise<string | null>,
        preparingPhase: "preparing_photo" | "preparing_album",
      ) => {
        if (ocrBusy) return;
        if (!ocrUnlocked) {
          revealPaywall();
          return;
        }
        setUiState({ busy: true, message: "" });
        try {
          const uri = await getUri();
          if (!uri) {
            setUiState(OCR_UI_IDLE);
            return;
          }

          reportProgress(preparingPhase);
          const { words, rawText } = await ocrWordsFromImage(
            uri,
            reportProgress,
          );

          if (words.length === 0) {
            onOcrOutcome?.(
              rawText
                ? OCR_OUTCOME_MESSAGES.emptyUnparsed
                : OCR_OUTCOME_MESSAGES.empty,
            );
            return;
          }

          onOcrResult(words);
          onOcrOutcome?.(OCR_OUTCOME_MESSAGES.success(words.length));
        } catch (error) {
          onOcrOutcome?.(
            error instanceof Error
              ? error.message
              : OCR_OUTCOME_MESSAGES.failed,
          );
        } finally {
          setUiState(OCR_UI_IDLE);
        }
      },
      [
        ocrBusy,
        ocrUnlocked,
        onOcrOutcome,
        onOcrResult,
        revealPaywall,
        reportProgress,
        setUiState,
      ],
    );

    const processOcr = useCallback(
      () => runOcr(takePhoto, "preparing_photo"),
      [runOcr],
    );

    const processAlbum = useCallback(
      () => runOcr(pickFromAlbum, "preparing_album"),
      [runOcr],
    );

    useImperativeHandle(
      ref,
      () => ({
        processPhoto: processOcr,
        processAlbum,
        busy: ocrBusy,
      }),
      [processOcr, processAlbum, ocrBusy],
    );

    const handleUnlockSubmit = useCallback(() => {
      if (unlockCode.length !== 4) return;
      setUnlockError(false);
      const ok = onUnlockOcr(unlockCode);
      if (ok) {
        setShowUnlock(false);
        setUnlockCode("");
      } else {
        setUnlockError(true);
        setUnlockCode("");
      }
    }, [unlockCode, onUnlockOcr]);

    // ---- Paywall view (step 1: show WeChat ID) ----
    if (!ocrUnlocked && !showUnlock) {
      return (
        <View
          style={[
            styles.container,
            styles.paywallContainer,
            { borderColor: colors.border },
          ]}
        >
          <TouchableOpacity
            style={styles.paywallHeader}
            onPress={togglePaywall}
            activeOpacity={0.6}
          >
            <Text style={styles.paywallLockIcon}>🔒</Text>
            <Text style={[styles.paywallTitle, { color: colors.foreground }]}>
              拍照识别
            </Text>
            <Text style={[styles.chevron, { color: colors.muted }]}>
              {paywallCollapsed ? "▸" : "▾"}
            </Text>
          </TouchableOpacity>
          {!paywallCollapsed && (
            <>
              <Text style={[styles.paywallDesc, { color: colors.muted }]}>
                拍照或从相册选取图片，自动识别图片中的英文单词，快速生成听写列表。
              </Text>
              <View style={styles.priceBadge}>
                <Text
                  style={[styles.priceAmount, { color: colors.foreground }]}
                >
                  ¥9.9
                </Text>
                <Text style={[styles.priceLabel, { color: colors.muted }]}>
                  一次性解锁，永久使用
                </Text>
              </View>
              <View style={styles.wechatRow}>
                <Text style={styles.wechatIcon}>💬</Text>
                <Text style={[styles.wechatLabel, { color: colors.muted }]}>
                  添加微信号
                </Text>
                <Text style={[styles.wechatId, { color: colors.primary }]}>
                  {config.wechatId}
                </Text>
                <Text style={[styles.wechatLabel, { color: colors.muted }]}>
                  完成支付
                </Text>
              </View>
              <TouchableOpacity
                style={[styles.unlockBtn, { backgroundColor: colors.primary }]}
                onPress={() => setShowUnlock(true)}
                activeOpacity={0.7}
              >
                <Text
                  style={[styles.unlockBtnText, { color: colors.background }]}
                >
                  我已支付，输入解锁码
                </Text>
              </TouchableOpacity>
            </>
          )}
        </View>
      );
    }

    // ---- Unlock code input (step 2) ----
    if (!ocrUnlocked && showUnlock) {
      return (
        <View
          style={[
            styles.container,
            styles.paywallContainer,
            { borderColor: colors.border },
          ]}
        >
          <Text style={[styles.paywallTitle, { color: colors.foreground }]}>
            输入解锁码
          </Text>
          <Text style={[styles.paywallDesc, { color: colors.muted }]}>
            支付完成后，请输入您收到的 4 位解锁码
          </Text>
          <TextInput
            style={[
              styles.unlockInput,
              {
                borderColor: unlockError ? colors.danger : colors.border,
                color: colors.foreground,
                backgroundColor: colors.surface,
              },
            ]}
            autoCapitalize="characters"
            maxLength={4}
            value={unlockCode}
            onChangeText={(text) => {
              const filtered = text
                .toUpperCase()
                .split("")
                .filter((ch) => ALPHANUMERIC.test(ch))
                .join("")
                .slice(0, 4);
              setUnlockCode(filtered);
              setUnlockError(false);
            }}
            placeholder="••••"
            placeholderTextColor={colors.subtle}
            textAlign="center"
            autoFocus
          />
          {unlockError ? (
            <Text style={[styles.errorText, { color: colors.danger }]}>
              解锁码无效，请检查后重试
            </Text>
          ) : null}
          <View style={styles.unlockBtnRow}>
            <TouchableOpacity
              style={[styles.cancelBtn, { borderColor: colors.border }]}
              onPress={() => {
                setShowUnlock(false);
                setUnlockCode("");
                setUnlockError(false);
              }}
              activeOpacity={0.7}
            >
              <Text
                style={[styles.cancelBtnText, { color: colors.foreground }]}
              >
                返回
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[
                styles.unlockSubmitBtn,
                { backgroundColor: colors.primary },
                unlockCode.length !== 4 && styles.btnDisabled,
              ]}
              onPress={handleUnlockSubmit}
              disabled={unlockCode.length !== 4}
              activeOpacity={0.7}
            >
              <Text
                style={[
                  styles.unlockSubmitBtnText,
                  { color: colors.background },
                ]}
              >
                确认
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      );
    }

    // ---- Normal OCR view (unlocked) ----
    if (hideActions) {
      return null;
    }

    return (
      <View style={styles.container}>
        <View style={styles.btnRow}>
          <TouchableOpacity
            style={[
              styles.actionBtn,
              {
                backgroundColor: colors.primary,
                shadowColor: colors.primary,
                shadowOpacity: 0.3,
                shadowRadius: 8,
                shadowOffset: { width: 0, height: 4 },
                elevation: 4,
              },
              ocrBusy && styles.btnDisabled,
            ]}
            onPress={processOcr}
            disabled={ocrBusy}
            activeOpacity={0.7}
          >
            {ocrBusy ? (
              <ActivityIndicator size="small" color={colors.background} />
            ) : (
              <View style={styles.actionBtnContent}>
                <Ionicons name="camera" size={16} color={colors.background} />
                <Text
                  style={[styles.actionBtnText, { color: colors.background }]}
                >
                  拍照
                </Text>
              </View>
            )}
          </TouchableOpacity>
          <TouchableOpacity
            style={[
              styles.actionBtn,
              {
                backgroundColor: colors.surface,
                borderColor: colors.border,
                borderWidth: 1,
              },
              ocrBusy && styles.btnDisabled,
            ]}
            onPress={processAlbum}
            disabled={ocrBusy}
            activeOpacity={0.7}
          >
            {ocrBusy ? (
              <ActivityIndicator size="small" color={colors.foreground} />
            ) : (
              <View style={styles.actionBtnContent}>
                <Ionicons
                  name="images-outline"
                  size={16}
                  color={colors.foreground}
                />
                <Text
                  style={[styles.actionBtnText, { color: colors.foreground }]}
                >
                  相册
                </Text>
              </View>
            )}
          </TouchableOpacity>
        </View>
      </View>
    );
  },
);

const styles = StyleSheet.create({
  container: {
    gap: spacing.sm,
  },
  paywallContainer: {
    borderWidth: 1,
    borderRadius: radii.card,
    padding: spacing.md,
    alignItems: "center",
    gap: spacing.sm,
  },
  paywallHeader: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    width: "100%",
  },
  paywallLockIcon: {
    fontSize: 20,
  },
  paywallTitle: {
    fontSize: 16,
    fontWeight: "600",
  },
  chevron: {
    fontSize: 16,
    marginLeft: "auto",
  },
  paywallDesc: {
    fontSize: 13,
    textAlign: "center",
    lineHeight: 20,
  },
  wechatRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    flexWrap: "wrap",
    justifyContent: "center",
  },
  priceBadge: {
    alignItems: "center",
    gap: 2,
    marginVertical: 4,
  },
  priceAmount: {
    fontSize: 26,
    fontWeight: "800",
  },
  priceLabel: {
    fontSize: 12,
  },
  wechatIcon: {
    fontSize: 16,
  },
  wechatLabel: {
    fontSize: 13,
  },
  wechatId: {
    fontSize: 15,
    fontWeight: "700",
  },
  unlockBtn: {
    marginTop: 4,
    minHeight: 44,
    paddingHorizontal: 24,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
  },
  unlockBtnText: {
    fontSize: 15,
    fontWeight: "600",
  },
  unlockInput: {
    width: "100%",
    height: 52,
    borderWidth: 2,
    borderRadius: 12,
    paddingHorizontal: 16,
    fontSize: 28,
    fontWeight: "600",
    letterSpacing: 12,
    textAlign: "center",
  },
  errorText: {
    fontSize: 13,
  },
  unlockBtnRow: {
    flexDirection: "row",
    gap: 10,
    width: "100%",
  },
  cancelBtn: {
    flex: 1,
    minHeight: 44,
    borderRadius: radii.button,
    borderWidth: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  cancelBtnText: {
    fontSize: 15,
    fontWeight: "600",
  },
  unlockSubmitBtn: {
    flex: 1,
    minHeight: 44,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
  },
  unlockSubmitBtnText: {
    fontSize: 15,
    fontWeight: "600",
  },
  btnRow: {
    flexDirection: "row",
    gap: spacing.sm,
  },
  actionBtn: {
    flex: 1,
    minWidth: 72,
    minHeight: 32,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: spacing.sm,
  },
  actionBtnContent: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.xs,
  },
  actionBtnText: {
    fontSize: 13,
    fontWeight: "600",
    lineHeight: 16,
  },
  btnDisabled: {
    opacity: 0.4,
  },
});
