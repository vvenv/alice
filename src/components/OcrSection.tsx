import { Ionicons } from "@expo/vector-icons";
import {
  forwardRef,
  useCallback,
  useImperativeHandle,
  useState,
} from "react";
import {
  ActivityIndicator,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";

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
  onOcrResult: (words: string[]) => void;
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

export const OcrSection = forwardRef<OcrSectionHandle, OcrSectionProps>(
  function OcrSection(
    { onOcrResult, hideActions = false, onOcrStateChange, onOcrOutcome },
    ref,
  ) {
    const colors = useThemeColors();
    const [ocrBusy, setOcrBusy] = useState(false);

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

    const runOcr = useCallback(
      async (
        getUri: () => Promise<string | null>,
        preparingPhase: "preparing_photo" | "preparing_album",
      ) => {
        if (ocrBusy) return;
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
      [ocrBusy, onOcrOutcome, onOcrResult, reportProgress, setUiState],
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
