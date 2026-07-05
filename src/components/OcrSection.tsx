import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  ViewStyle,
} from "react-native";

import { takePhoto, pickFromAlbum, ocrWordsFromImage } from "../lib/ocr";
import { useThemeColors, type ThemeColors } from "../lib/theme";
import { radii } from "../lib/designTokens";

interface OcrSectionProps {
  wordInput: string;
  onOcrResult: (words: string[]) => void;
}

export function OcrSection({ wordInput, onOcrResult }: OcrSectionProps) {
  const colors = useThemeColors();
  const [ocrBusy, setOcrBusy] = useState(false);
  const [ocrStatus, setOcrStatus] = useState("");

  const runOcr = useCallback(
    async (getUri: () => Promise<string | null>, messagePrefix: string) => {
      if (ocrBusy) return;
      setOcrBusy(true);
      try {
        const uri = await getUri();
        if (!uri) {
          setOcrBusy(false);
          return;
        }

        setOcrStatus(`${messagePrefix}，准备识别…`);
        const { words, rawText } = await ocrWordsFromImage(uri, setOcrStatus);

        if (words.length === 0) {
          const hint = rawText ? `：${rawText.slice(0, 40)}` : "";
          setOcrStatus(`未识别到英文单词${hint}`);
          return;
        }

        onOcrResult(words);
        setOcrStatus(`已识别 ${words.length} 个单词`);
      } catch (error) {
        setOcrStatus(error instanceof Error ? error.message : "识别失败");
      } finally {
        setOcrBusy(false);
      }
    },
    [ocrBusy, onOcrResult],
  );

  const processOcr = useCallback(() => runOcr(takePhoto, "已拍摄"), [runOcr]);

  const processAlbum = useCallback(
    () => runOcr(pickFromAlbum, "已选图"),
    [runOcr],
  );

  return (
    <View style={styles.container}>
      <View style={styles.btnRow}>
        <TouchableOpacity
          style={[
            primaryBtnStyle(colors),
            styles.halfBtn,
            ocrBusy && styles.btnDisabled,
          ]}
          onPress={processOcr}
          disabled={ocrBusy}
          activeOpacity={0.7}
        >
          {ocrBusy ? (
            <ActivityIndicator size="small" color={colors.background} />
          ) : (
            <Text style={[styles.primaryBtnText, { color: colors.background }]}>
             <Text style={styles.primaryBtnTextIcon}>📷</Text> 拍照
            </Text>
          )}
        </TouchableOpacity>

        <TouchableOpacity
          style={[
            secondaryBtnStyle(colors),
            styles.halfBtn,
            ocrBusy && styles.btnDisabled,
          ]}
          onPress={processAlbum}
          disabled={ocrBusy}
          activeOpacity={0.7}
        >
          {ocrBusy ? (
            <ActivityIndicator size="small" color={colors.background} />
          ) : (
            <Text style={[styles.secondaryBtnText, { color: colors.background }]}>
              <Text style={styles.secondaryBtnTextIcon}>🖼</Text> 相册
            </Text>
          )}
        </TouchableOpacity>
      </View>

      {ocrStatus ? (
        <View style={[styles.statusBox, { backgroundColor: colors.surface }]}>
          <Text style={[styles.statusText, { color: colors.muted }]}>
            {ocrStatus}
          </Text>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  btnRow: {
    flexDirection: "row",
    gap: 10,
  },
  halfBtn: {
    flex: 1,
  },
  primaryBtnText: {
    fontSize: 16,
    fontWeight: "600",
    display: "flex",
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  primaryBtnTextIcon: {
    fontSize: 24,
  },
  secondaryBtnText: {
    fontSize: 16,
    fontWeight: "600",
    display: "flex",
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  secondaryBtnTextIcon: {
    fontSize: 16,
  },
  btnDisabled: {
    opacity: 0.5,
  },
  statusBox: {
    borderRadius: radii.surface,
    paddingVertical: 8,
    paddingHorizontal: 12,
    alignItems: "center",
  },
  statusText: {
    fontSize: 13,
    textAlign: "center",
  },
});

const primaryBtnStyle = (colors: ThemeColors): ViewStyle => ({
  minHeight: 52,
  backgroundColor: colors.primary,
  borderRadius: radii.button,
  justifyContent: "center",
  alignItems: "center",
  paddingHorizontal: 20,
  shadowColor: colors.primary,
  shadowOpacity: 0.3,
  shadowRadius: 8,
  shadowOffset: { width: 0, height: 4 },
  elevation: 4,
});

const secondaryBtnStyle = (colors: ThemeColors): ViewStyle => ({
  minHeight: 52,
  backgroundColor: colors.secondary,
  borderRadius: radii.button,
  justifyContent: "center",
  alignItems: "center",
  paddingHorizontal: 20,
  shadowColor: colors.secondary,
  shadowOpacity: 0.3,
  shadowRadius: 8,
  shadowOffset: { width: 0, height: 4 },
  elevation: 4,
});
