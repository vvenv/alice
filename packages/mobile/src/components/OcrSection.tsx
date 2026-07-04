import { useCallback, useState } from "react";
import { ActivityIndicator, Alert, StyleSheet, Text, TouchableOpacity, View } from "react-native";

import { pickImageFromGallery, takePhoto, ocrWordsFromImage } from "../lib/ocr";
import { parseWords } from "../lib/dictation";
import { colors, radii, spacing } from "../lib/designTokens";

export type OcrMode = "append" | "replace";

interface OcrSectionProps {
  wordInput: string;
  onOcrResult: (words: string[], mode: OcrMode) => void;
}

export function OcrSection({ wordInput, onOcrResult }: OcrSectionProps) {
  const [ocrBusy, setOcrBusy] = useState(false);
  const [ocrMode, setOcrMode] = useState<OcrMode>("replace");
  const [ocrStatus, setOcrStatus] = useState("");

  const processOcrImage = useCallback(
    async (source: "camera" | "gallery", mode: OcrMode) => {
      if (ocrBusy) return;
      setOcrBusy(true);
      try {
        const uri =
          source === "camera"
            ? await takePhoto()
            : await pickImageFromGallery();
        if (!uri) {
          setOcrBusy(false);
          return;
        }

        setOcrStatus("已选图，准备识别…");
        const { words, rawText } = await ocrWordsFromImage(uri, setOcrStatus);

        if (words.length === 0) {
          const hint = rawText ? `：${rawText.slice(0, 40)}` : "";
          setOcrStatus(`未识别到英文单词${hint}`);
          return;
        }

        onOcrResult(
          mode === "replace" ? words : [...parseWords(wordInput), ...words],
          mode,
        );
        const action = mode === "replace" ? "已替换为" : "已追加";
        setOcrStatus(`${action} ${words.length} 个单词`);
      } catch (error) {
        setOcrStatus(
          error instanceof Error ? error.message : "识别失败",
        );
      } finally {
        setOcrBusy(false);
      }
    },
    [ocrBusy, onOcrResult, wordInput],
  );

  return (
    <View style={styles.container}>
      <View style={styles.buttonRow}>
        <TouchableOpacity
          style={[styles.primaryBtn, ocrBusy && styles.btnDisabled]}
          onPress={() => processOcrImage("camera", ocrMode)}
          disabled={ocrBusy}
          activeOpacity={0.7}
        >
          {ocrBusy ? (
            <ActivityIndicator size="small" color="#fff" />
          ) : (
            <Text style={styles.primaryBtnText}>📷 拍照识别</Text>
          )}
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.ghostBtn, ocrBusy && styles.btnDisabled]}
          onPress={() => processOcrImage("gallery", ocrMode)}
          disabled={ocrBusy}
          activeOpacity={0.7}
        >
          <Text style={styles.ghostBtnText}>🖼️ 相册</Text>
        </TouchableOpacity>
      </View>
      <View style={styles.modeRow}>
        <Text style={styles.modeLabel}>识别后</Text>
        <View style={styles.segment}>
          <TouchableOpacity
            style={[styles.segmentItem, ocrMode === "append" && styles.segmentItemActive]}
            disabled={ocrBusy}
            onPress={() => setOcrMode("append")}
            activeOpacity={0.6}
          >
            <Text style={[styles.segmentText, ocrMode === "append" && styles.segmentTextActive]}>
              追加
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.segmentItem, ocrMode === "replace" && styles.segmentItemActive]}
            disabled={ocrBusy}
            onPress={() => setOcrMode("replace")}
            activeOpacity={0.6}
          >
            <Text style={[styles.segmentText, ocrMode === "replace" && styles.segmentTextActive]}>
              替换
            </Text>
          </TouchableOpacity>
        </View>
      </View>
      {ocrStatus ? (
        <View style={styles.statusBox}>
          <Text style={styles.statusText}>{ocrStatus}</Text>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  buttonRow: {
    flexDirection: "row",
    gap: 12,
  },
  primaryBtn: {
    flex: 1,
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
  },
  primaryBtnText: {
    color: colors.background,
    fontSize: 17,
    fontWeight: "600",
  },
  ghostBtn: {
    flex: 1,
    minHeight: 52,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.background,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 20,
  },
  ghostBtnText: {
    color: colors.secondary,
    fontSize: 17,
    fontWeight: "600",
  },
  btnDisabled: {
    opacity: 0.5,
  },
  modeRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
  },
  modeLabel: {
    fontSize: 12,
    color: colors.muted,
    flexShrink: 0,
  },
  segment: {
    flex: 1,
    flexDirection: "row",
    backgroundColor: colors.surfaceRaised,
    borderRadius: radii.surface,
    padding: 4,
    gap: 6,
  },
  segmentItem: {
    flex: 1,
    alignItems: "center",
    borderRadius: radii.control,
    paddingVertical: 6,
    paddingHorizontal: 8,
  },
  segmentItemActive: {
    backgroundColor: colors.background,
    shadowColor: "#000",
    shadowOpacity: 0.1,
    shadowRadius: 2,
    shadowOffset: { width: 0, height: 1 },
    elevation: 2,
  },
  segmentText: {
    fontSize: 14,
    fontWeight: "500",
    color: colors.muted,
  },
  segmentTextActive: {
    color: colors.foreground,
  },
  statusBox: {
    backgroundColor: colors.surface,
    borderRadius: radii.surface,
    paddingVertical: 8,
    paddingHorizontal: 12,
    alignItems: "center",
  },
  statusText: {
    fontSize: 13,
    color: colors.muted,
    textAlign: "center",
  },
});
