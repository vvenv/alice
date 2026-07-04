import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import { useWrongWords } from "../hooks/useWrongWords";
import { pickImageFromGallery, takePhoto, ocrWordsFromImage } from "../lib/ocr";
import { loadWordInput, saveWordInput } from "../lib/storage";
import {
  DEFAULT_TTS_VOICE,
  loadPersistedVoice,
  parseWords,
  saveTtsVoice,
  SYSTEM_TTS_VOICES,
} from "../lib/dictation";

const SAMPLE_WORDS = "apple banana cat dog elephant fish grape";

interface HomeScreenProps {
  onStartDictation: (params: {
    words: string[];
    voice: string;
    intervalSec: number;
    autoNext: boolean;
  }) => void;
}

export function HomeScreen({ onStartDictation }: HomeScreenProps) {
  const [wordInput, setWordInput] = useState("");
  const [intervalSec, setIntervalSec] = useState(8);
  const [autoNext, setAutoNext] = useState(true);
  const [voice, setVoice] = useState(DEFAULT_TTS_VOICE);
  const [ocrBusy, setOcrBusy] = useState(false);
  const [ocrStatus, setOcrStatus] = useState("");

  const { wrongWords, exportWrong, clearWrong, removeWrongWord } =
    useWrongWords();

  const wordCount = useMemo(() => parseWords(wordInput).length, [wordInput]);

  // Load persisted data on mount
  useEffect(() => {
    (async () => {
      const savedInput = await loadWordInput();
      if (savedInput) setWordInput(savedInput);
      const savedVoice = await loadPersistedVoice();
      setVoice(savedVoice);
    })();
  }, []);

  // Persist word input changes
  useEffect(() => {
    saveWordInput(wordInput);
  }, [wordInput]);

  const handleStart = useCallback(() => {
    const words = parseWords(wordInput);
    if (words.length === 0) {
      Alert.alert("提示", "请先输入单词列表");
      return;
    }
    onStartDictation({ words, voice, intervalSec, autoNext });
  }, [wordInput, voice, intervalSec, autoNext, onStartDictation]);

  const handleOcr = useCallback(
    async (mode: "append" | "replace") => {
      Alert.alert("选择方式", "拍照或从相册选择？", [
        { text: "拍照", onPress: () => processOcrImage("camera", mode) },
        {
          text: "从相册选择",
          onPress: () => processOcrImage("gallery", mode),
        },
        { text: "取消", style: "cancel" },
      ]);
    },
    [wordInput],
  );

  const processOcrImage = useCallback(
    async (source: "camera" | "gallery", mode: "append" | "replace") => {
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
        const { words } = await ocrWordsFromImage(uri, setOcrStatus);

        if (words.length === 0) {
          setOcrStatus("未识别到英文单词");
          return;
        }

        const nextWords =
          mode === "replace"
            ? words
            : [...parseWords(wordInput), ...words];
        setWordInput(nextWords.join("\n"));
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
    [ocrBusy, wordInput],
  );

  const handleExport = useCallback(async () => {
    const msg = await exportWrong();
    if (msg) Alert.alert("提示", msg);
  }, [exportWrong]);

  const handleClearWrong = useCallback(() => {
    if (wrongWords.length === 0) return;
    Alert.alert("确认", "清空所有错词？", [
      { text: "取消", style: "cancel" },
      {
        text: "清空",
        style: "destructive",
        onPress: () => {
          clearWrong();
        },
      },
    ]);
  }, [wrongWords, clearWrong]);

  const handleRemoveWord = removeWrongWord;

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
      >
        {/* Header */}
        <Text style={styles.title}>听写练习</Text>

        {/* OCR Buttons */}
        <View style={styles.ocrRow}>
          <TouchableOpacity
            style={[styles.ocrBtn, ocrBusy && styles.btnDisabled]}
            onPress={() => handleOcr("replace")}
            disabled={ocrBusy}
            activeOpacity={0.7}
          >
            {ocrBusy ? (
              <ActivityIndicator size="small" color="#fff" />
            ) : (
              <Text style={styles.ocrBtnText}>拍照识别 (替换)</Text>
            )}
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.ocrBtn, styles.ocrBtnOutline, ocrBusy && styles.btnDisabled]}
            onPress={() => handleOcr("append")}
            disabled={ocrBusy}
            activeOpacity={0.7}
          >
            <Text style={[styles.ocrBtnText, styles.ocrBtnTextOutline]}>
              拍照识别 (追加)
            </Text>
          </TouchableOpacity>
        </View>
        {ocrStatus ? (
          <Text style={styles.ocrStatus}>{ocrStatus}</Text>
        ) : null}

        {/* Word Input */}
        <View style={styles.section}>
          <TextInput
            style={styles.textArea}
            multiline
            numberOfLines={4}
            placeholder="每行一个，或用逗号/空格分隔\n例：apple banana cat"
            placeholderTextColor="#aaa"
            value={wordInput}
            onChangeText={setWordInput}
            textAlignVertical="top"
          />
          <View style={styles.inputFooter}>
            <Text style={styles.wordCount}>共 {wordCount} 个单词</Text>
            <View style={styles.inputActions}>
              <TouchableOpacity
                style={styles.smallBtn}
                onPress={() => setWordInput(SAMPLE_WORDS)}
              >
                <Text style={styles.smallBtnText}>示例</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.smallBtn}
                onPress={() => setWordInput("")}
              >
                <Text style={styles.smallBtnText}>清空</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>

        {/* Voice Selector */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>音色</Text>
          <View style={styles.segmentRow}>
            {SYSTEM_TTS_VOICES.map((item) => {
              const active = voice === item.id;
              return (
                <TouchableOpacity
                  key={item.id}
                  style={[
                    styles.segmentItem,
                    active && styles.segmentItemActive,
                  ]}
                  onPress={() => {
                    setVoice(item.id);
                    saveTtsVoice(item.id);
                  }}
                >
                  <Text
                    style={[
                      styles.segmentText,
                      active && styles.segmentTextActive,
                    ]}
                  >
                    {item.label}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>
        </View>

        {/* Interval & Auto-next */}
        <View style={styles.section}>
          <View style={styles.settingRow}>
            <Text style={styles.sectionTitle}>间隔</Text>
            <Text style={styles.intervalValue}>{intervalSec.toFixed(1)}s</Text>
          </View>
          <View style={styles.sliderRow}>
            <Text style={styles.sliderLabel}>1s</Text>
            <View style={styles.sliderTrack}>
              <View
                style={[
                  styles.sliderFill,
                  {
                    width: `${((intervalSec - 1) / 9) * 100}%`,
                  },
                ]}
              />
            </View>
            <Text style={styles.sliderLabel}>10s</Text>
          </View>
          <View style={styles.sliderButtons}>
            {[1, 2, 4, 6, 8, 10].map((v) => (
              <TouchableOpacity
                key={v}
                style={[
                  styles.sliderBtn,
                  intervalSec === v && styles.sliderBtnActive,
                ]}
                onPress={() => setIntervalSec(v)}
              >
                <Text
                  style={[
                    styles.sliderBtnText,
                    intervalSec === v && styles.sliderBtnTextActive,
                  ]}
                >
                  {v}s
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          <View style={styles.autoRow}>
            <Text style={styles.autoLabel}>自动下一词</Text>
            <Switch
              value={autoNext}
              onValueChange={setAutoNext}
              trackColor={{ false: "#ddd", true: "#93b4f7" }}
              thumbColor={autoNext ? "#4a6cf7" : "#f4f4f4"}
            />
          </View>
        </View>

        {/* Start Button */}
        <TouchableOpacity
          style={styles.startBtn}
          onPress={handleStart}
          activeOpacity={0.7}
        >
          <Text style={styles.startBtnText}>
            &#9654; 开始听写 ({wordCount} 词)
          </Text>
        </TouchableOpacity>

        {/* Wrong Words Panel */}
        <View style={styles.wrongSection}>
          <View style={styles.wrongHeader}>
            <Text style={styles.wrongTitle}>错词本</Text>
            <View style={styles.wrongActions}>
              <TouchableOpacity style={styles.smallBtn} onPress={handleExport}>
                <Text style={styles.smallBtnText}>导出</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.smallBtn}
                onPress={handleClearWrong}
              >
                <Text style={styles.smallBtnText}>清空</Text>
              </TouchableOpacity>
            </View>
          </View>
          {wrongWords.length === 0 ? (
            <Text style={styles.emptyWrong}>尚无错词</Text>
          ) : (
            <View style={styles.chipRow}>
              {wrongWords.map((word) => (
                <TouchableOpacity
                  key={word}
                  style={styles.chip}
                  onPress={() => handleRemoveWord(word)}
                  activeOpacity={0.7}
                >
                  <Text style={styles.chipText}>{word}</Text>
                  <Text style={styles.chipRemove}> ×</Text>
                </TouchableOpacity>
              ))}
            </View>
          )}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#f8f9fa",
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
    gap: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: "700",
    color: "#1a1a2e",
    textAlign: "center",
  },

  // OCR
  ocrRow: {
    flexDirection: "row",
    gap: 12,
  },
  ocrBtn: {
    flex: 1,
    height: 44,
    backgroundColor: "#4a6cf7",
    borderRadius: 10,
    justifyContent: "center",
    alignItems: "center",
  },
  ocrBtnOutline: {
    backgroundColor: "transparent",
    borderWidth: 1.5,
    borderColor: "#4a6cf7",
  },
  ocrBtnText: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "600",
  },
  ocrBtnTextOutline: {
    color: "#4a6cf7",
  },
  btnDisabled: {
    opacity: 0.5,
  },
  ocrStatus: {
    textAlign: "center",
    color: "#888",
    fontSize: 13,
  },

  // Section
  section: {
    gap: 12,
  },
  sectionTitle: {
    fontSize: 15,
    fontWeight: "600",
    color: "#555",
  },

  // Text area
  textArea: {
    borderWidth: 1.5,
    borderColor: "#e2e2e2",
    borderRadius: 12,
    padding: 14,
    fontSize: 15,
    backgroundColor: "#fff",
    color: "#1a1a2e",
    minHeight: 100,
  },
  inputFooter: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  wordCount: {
    fontSize: 13,
    color: "#999",
  },
  inputActions: {
    flexDirection: "row",
    gap: 8,
  },
  smallBtn: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 6,
    backgroundColor: "#f0f0f0",
  },
  smallBtnText: {
    fontSize: 13,
    color: "#666",
  },

  // Voice segment
  segmentRow: {
    flexDirection: "row",
    backgroundColor: "#eee",
    borderRadius: 10,
    padding: 3,
  },
  segmentItem: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 8,
    alignItems: "center",
  },
  segmentItemActive: {
    backgroundColor: "#fff",
    shadowColor: "#000",
    shadowOpacity: 0.08,
    shadowRadius: 4,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  segmentText: {
    fontSize: 14,
    color: "#777",
  },
  segmentTextActive: {
    color: "#1a1a2e",
    fontWeight: "600",
  },

  // Interval
  settingRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  intervalValue: {
    fontSize: 16,
    fontWeight: "700",
    color: "#4a6cf7",
  },
  sliderRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  sliderLabel: {
    fontSize: 12,
    color: "#aaa",
  },
  sliderTrack: {
    flex: 1,
    height: 6,
    backgroundColor: "#e2e2e2",
    borderRadius: 3,
    overflow: "hidden",
  },
  sliderFill: {
    height: "100%",
    backgroundColor: "#4a6cf7",
    borderRadius: 3,
  },
  sliderButtons: {
    flexDirection: "row",
    gap: 8,
  },
  sliderBtn: {
    flex: 1,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: "#f0f0f0",
    alignItems: "center",
  },
  sliderBtnActive: {
    backgroundColor: "#4a6cf7",
  },
  sliderBtnText: {
    fontSize: 13,
    color: "#666",
    fontWeight: "500",
  },
  sliderBtnTextActive: {
    color: "#fff",
    fontWeight: "600",
  },

  // Auto
  autoRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  autoLabel: {
    fontSize: 15,
    fontWeight: "600",
    color: "#555",
  },

  // Start button
  startBtn: {
    height: 52,
    backgroundColor: "#4a6cf7",
    borderRadius: 12,
    justifyContent: "center",
    alignItems: "center",
    shadowColor: "#4a6cf7",
    shadowOpacity: 0.3,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
    elevation: 4,
  },
  startBtnText: {
    color: "#fff",
    fontSize: 18,
    fontWeight: "700",
  },

  // Wrong words
  wrongSection: {
    borderTopWidth: 1,
    borderTopColor: "#e2e2e2",
    paddingTop: 16,
    gap: 12,
  },
  wrongHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  wrongTitle: {
    fontSize: 15,
    fontWeight: "600",
    color: "#555",
  },
  wrongActions: {
    flexDirection: "row",
    gap: 8,
  },
  emptyWrong: {
    textAlign: "center",
    color: "#bbb",
    fontSize: 14,
    paddingVertical: 16,
    backgroundColor: "#f0f0f0",
    borderRadius: 10,
  },
  chipRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 8,
  },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#e8e8e8",
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
  },
  chipText: {
    fontSize: 14,
    color: "#333",
  },
  chipRemove: {
    fontSize: 16,
    color: "#bbb",
    marginLeft: 4,
  },
});
