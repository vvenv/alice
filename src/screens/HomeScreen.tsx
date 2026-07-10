import { Ionicons } from "@expo/vector-icons";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Text,
  View,
} from "react-native";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { SafeAreaView } from "react-native-safe-area-context";

import { ConfirmDialog } from "../components/ConfirmDialog";
import { HistoryDrawer } from "../components/HistoryDrawer";
import { OcrSection } from "../components/OcrSection";
import { PlaybackControls } from "../components/PlaybackControls";
import { Toast } from "../components/Toast";
import { WordInputSection } from "../components/WordInputSection";
import { useToast } from "../hooks/useToast";
import type { RootStackParamList } from "../navigation/types";
import { parseWords } from "../lib/dictation";
import {
  loadPersistedWrongWords,
  loadWordInput,
  saveWordInput,
  loadWordHistory,
  addWordHistory,
  deleteWordHistory,
  clearWordHistory,
  WordHistoryEntry,
} from "../lib/storage";
import { loadOcrUnlockState, verifyUnlockCode } from "../lib/auth";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors, useThemeMode } from "../lib/theme";

const SAMPLE_WORDS = "apple banana cat dog elephant fish grape";
const WORD_INPUT_SAVE_DEBOUNCE_MS = 500;

function shuffleArray<T>(arr: T[]): T[] {
  const shuffled = [...arr];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j]!, shuffled[i]!];
  }
  return shuffled;
}

type HomeNavigation = NativeStackNavigationProp<RootStackParamList, "Home">;

function isDefaultEntry(entry: WordHistoryEntry): boolean {
  return entry.id.startsWith("default_");
}

function wordCount(text: string): number {
  return parseWords(text).length;
}

export function HomeScreen() {
  const navigation = useNavigation<HomeNavigation>();
  const colors = useThemeColors();
  const { mode, toggleTheme } = useThemeMode();
  const [ready, setReady] = useState(false);
  const [wordInput, setWordInput] = useState("");
  const [intervalSec, setIntervalSec] = useState(4.5);
  const [autoNext, setAutoNext] = useState(true);
  const [startIndex, setStartIndex] = useState(0);
  const [shuffle, setShuffle] = useState(false);
  const [ocrUnlocked, setOcrUnlocked] = useState(false);
  const [history, setHistory] = useState<WordHistoryEntry[]>([]);
  const [historyDrawerVisible, setHistoryDrawerVisible] = useState(false);

  // Confirm dialog state
  const [dialog, setDialog] = useState<{
    visible: boolean;
    title: string;
    message: string;
    confirmLabel: string;
    action: () => void;
  } | null>(null);

  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const { toast, showToast } = useToast();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [savedInput, , persistedOcrUnlocked, savedHistory] =
        await Promise.all([
          loadWordInput(),
          loadPersistedWrongWords(),
          loadOcrUnlockState(),
          loadWordHistory(),
        ]);
      if (cancelled) return;
      if (savedInput) setWordInput(savedInput);
      setOcrUnlocked(persistedOcrUnlocked);
      setHistory(savedHistory);
      setReady(true);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Debounced persistence to avoid writing AsyncStorage on every keystroke
  useEffect(() => {
    if (!ready) return;
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      saveWordInput(wordInput);
    }, WORD_INPUT_SAVE_DEBOUNCE_MS);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [wordInput, ready]);

  // Clamp startIndex when word count drops below current startIndex
  useEffect(() => {
    const count = wordCount(wordInput);
    if (startIndex >= count && count > 0) {
      setStartIndex(Math.max(0, count - 1));
    } else if (count === 0) {
      setStartIndex(0);
    }
  }, [wordInput, startIndex]);

  const handleOcrResult = useCallback((words: string[]) => {
    setWordInput(words.join("\n"));
  }, []);

  const handleUnlockOcr = useCallback((code: string): boolean => {
    const ok = verifyUnlockCode(code);
    if (ok) setOcrUnlocked(true);
    return ok;
  }, []);

  const handleStart = useCallback(() => {
    const allWords = parseWords(wordInput);
    if (allWords.length === 0) {
      showToast("请先输入单词列表");
      return;
    }
    const clampedStart = Math.min(startIndex, allWords.length - 1);
    let words = allWords.slice(clampedStart);
    if (shuffle) {
      words = shuffleArray(words);
    }
    // Save to history before navigating
    addWordHistory(wordInput).then(() => loadWordHistory().then(setHistory));
    navigation.navigate("Dictation", {
      words,
      intervalSec,
      autoNext,
    });
  }, [
    autoNext,
    intervalSec,
    navigation,
    showToast,
    shuffle,
    startIndex,
    wordInput,
  ]);

  const handleApplyHistory = useCallback(
    (text: string) => {
      setWordInput(text);
      showToast("已载入历史记录");
    },
    [showToast],
  );

  const handleDeleteHistory = useCallback((id: string) => {
    setDialog({
      visible: true,
      title: "删除记录",
      message: "确定要删除这条历史记录吗？",
      confirmLabel: "删除",
      action: () => {
        setHistory((prev) => prev.filter((e) => e.id !== id));
        deleteWordHistory(id);
      },
    });
  }, []);

  const handleClearHistory = useCallback(() => {
    const userEntries = history.filter((e) => !isDefaultEntry(e));
    if (userEntries.length === 0) return;
    setDialog({
      visible: true,
      title: "清空历史",
      message: "确定要清空自定义历史记录吗？\n内置词库不会被清除。",
      confirmLabel: "清空",
      action: () => {
        clearWordHistory().then(() => loadWordHistory().then(setHistory));
      },
    });
  }, [history]);

  if (!ready) {
    return (
      <View
        style={[styles.loadingContainer, { backgroundColor: colors.surface }]}
      >
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <SafeAreaView
      style={[styles.safeArea, { backgroundColor: colors.background }]}
      edges={["top", "bottom", "left", "right"]}
    >
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <View style={styles.header}>
          <Text style={[styles.title, { color: colors.foreground }]}>
            Alice Dictation
          </Text>
          <TouchableOpacity
            style={[
              styles.themeBtn,
              {
                borderColor: colors.border,
                backgroundColor: colors.surface,
              },
            ]}
            onPress={toggleTheme}
            activeOpacity={0.7}
          >
            <Ionicons
              name={mode === "dark" ? "sunny" : "moon"}
              size={18}
              color={colors.foreground}
            />
          </TouchableOpacity>
        </View>

        <ScrollView
          style={styles.scroll}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          scrollEnabled={false}
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.content}>
            <OcrSection
              wordInput={wordInput}
              ocrUnlocked={ocrUnlocked}
              onOcrResult={handleOcrResult}
              onUnlockOcr={handleUnlockOcr}
              extraActions={
                ocrUnlocked
                  ? [
                      {
                        icon: "time-outline" as const,
                        label: "历史",
                        onPress: () => setHistoryDrawerVisible(true),
                      },
                    ]
                  : undefined
              }
            />
            <WordInputSection
              value={wordInput}
              onChange={setWordInput}
              onSetSample={() => setWordInput(SAMPLE_WORDS)}
              onClear={() => setWordInput("")}
              startIndex={startIndex}
              onStartIndexChange={setStartIndex}
            />

            {/* History entry — shown when OCR is locked (when unlocked, the
                history shortcut lives in the OCR button row above) */}
            {!ocrUnlocked && (
              <TouchableOpacity
                style={[
                  styles.historyEntryBtn,
                  {
                    backgroundColor: colors.surfaceSunken,
                    borderColor: colors.borderSubtle,
                  },
                ]}
                onPress={() => setHistoryDrawerVisible(true)}
                activeOpacity={0.7}
              >
                <Ionicons name="time-outline" size={20} color={colors.muted} />
                <View style={styles.historyEntryInfo}>
                  <Text
                    style={[styles.historyEntryLabel, { color: colors.muted }]}
                  >
                    历史记录
                  </Text>
                  <Text
                    style={[styles.historyEntrySub, { color: colors.subtle }]}
                  >
                    {history.length} 条记录
                  </Text>
                </View>
                <Ionicons
                  name="chevron-forward"
                  size={18}
                  color={colors.subtle}
                />
              </TouchableOpacity>
            )}
          </View>
        </ScrollView>

        <View style={[styles.bottomPanel, { borderTopColor: colors.border }]}>
          <PlaybackControls
            intervalSec={intervalSec}
            autoNext={autoNext}
            onIntervalChange={setIntervalSec}
            onAutoNextChange={setAutoNext}
            onPlayToggle={handleStart}
            shuffle={shuffle}
            onShuffleChange={setShuffle}
          />
        </View>
        <Toast message={toast} />
        <ConfirmDialog
          visible={dialog?.visible}
          title={dialog?.title}
          message={dialog?.message}
          confirmLabel={dialog?.confirmLabel}
          destructive
          onConfirm={dialog?.action ?? (() => {})}
          onCancel={() =>
            setDialog({
              ...dialog!,
              visible: false,
            })
          }
        />
        <HistoryDrawer
          visible={historyDrawerVisible}
          history={history}
          onClose={() => setHistoryDrawerVisible(false)}
          onApply={handleApplyHistory}
          onDelete={handleDeleteHistory}
          onClear={handleClearHistory}
        />
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  container: {
    flex: 1,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  title: {
    fontSize: 22,
    fontWeight: "700",
  },
  themeBtn: {
    width: 36,
    height: 36,
    borderRadius: radii.full,
    borderWidth: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    minHeight: 0,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.sm,
    paddingBottom: spacing.md,
  },
  content: {
    flex: 1,
    minHeight: 0,
    gap: spacing.lg,
    width: "100%",
    alignSelf: "center",
  },
  loadingContainer: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  bottomPanel: {
    borderTopWidth: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.md,
    width: "100%",
    alignSelf: "center",
  },

  // History entry button
  historyEntryBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    borderRadius: radii.surface,
    borderWidth: 1,
    padding: spacing.lg,
  },
  historyEntryInfo: {
    flex: 1,
    gap: 2,
  },
  historyEntryLabel: {
    fontSize: 14,
    fontWeight: "600",
  },
  historyEntrySub: {
    fontSize: 12,
  },
});
