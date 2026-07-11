import { Ionicons } from "@expo/vector-icons";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  TouchableOpacity,
  Text,
  View,
} from "react-native";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import {
  SafeAreaView,
  useSafeAreaInsets,
} from "react-native-safe-area-context";

import { ConfirmDialog } from "../components/ConfirmDialog";
import { HistoryDrawer } from "../components/HistoryDrawer";
import { OcrSection, type OcrSectionHandle } from "../components/OcrSection";
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
import { clearTtsCache } from "../lib/tts";

const SAMPLE_WORDS = "apple\nbanana\ncat\ndog\nelephant\nfish\ngrape";
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

type MenuItem = {
  key: string;
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  onPress: () => void;
  disabled?: boolean;
  accent?: boolean;
};

export function HomeScreen() {
  const navigation = useNavigation<HomeNavigation>();
  const insets = useSafeAreaInsets();
  const colors = useThemeColors();
  const { mode, toggleTheme } = useThemeMode();
  const [ready, setReady] = useState(false);
  const [wordInput, setWordInput] = useState("");
  const [intervalSec, setIntervalSec] = useState(4.5);
  const [autoNext, setAutoNext] = useState(true);
  const [startIndex, setStartIndex] = useState(0);
  const [shuffle, setShuffle] = useState(false);
  const [isDisplayMode, setIsDisplayMode] = useState(true);
  const [ocrUnlocked, setOcrUnlocked] = useState(false);
  const [history, setHistory] = useState<WordHistoryEntry[]>([]);
  const [historyDrawerVisible, setHistoryDrawerVisible] = useState(false);
  const [menuVisible, setMenuVisible] = useState(false);
  const ocrRef = useRef<OcrSectionHandle>(null);

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

  const handleClearTtsCache = useCallback(() => {
    setDialog({
      visible: true,
      title: "清空发音缓存",
      message: "确定要删除本地缓存的有道发音文件吗？\n下次听写会重新下载。",
      confirmLabel: "清空",
      action: () => {
        clearTtsCache()
          .then((count) => {
            showToast(
              count > 0 ? `已清空 ${count} 个发音缓存` : "暂无发音缓存",
            );
          })
          .catch(() => {
            showToast("清空发音缓存失败");
          });
      },
    });
  }, [showToast]);

  const parsedWordCount = wordCount(wordInput);
  const canToggleDisplayMode = parsedWordCount > 0;
  const effectiveDisplayMode = isDisplayMode && canToggleDisplayMode;

  const closeMenu = useCallback(() => setMenuVisible(false), []);

  const runMenuAction = useCallback(
    (action: () => void) => {
      closeMenu();
      // Let the menu close before opening camera / another modal
      requestAnimationFrame(action);
    },
    [closeMenu],
  );

  const menuItems: MenuItem[] = [
    {
      key: "photo",
      icon: "camera-outline",
      label: "拍照",
      onPress: () => runMenuAction(() => ocrRef.current?.processPhoto()),
    },
    {
      key: "album",
      icon: "images-outline",
      label: "相册",
      onPress: () => runMenuAction(() => ocrRef.current?.processAlbum()),
    },
    {
      key: "history",
      icon: "time-outline",
      label: "历史",
      onPress: () => runMenuAction(() => setHistoryDrawerVisible(true)),
    },
    {
      key: "cache",
      icon: "trash-outline",
      label: "清缓",
      onPress: () => runMenuAction(handleClearTtsCache),
    },
  ];

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
          <TouchableOpacity
            style={[
              styles.headerBtn,
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

          {canToggleDisplayMode ? (
            <View style={styles.headerCenter} pointerEvents="box-none">
              <TouchableOpacity
                style={[
                  styles.headerCenterBtn,
                  {
                    backgroundColor: effectiveDisplayMode
                      ? colors.primarySoft
                      : colors.surface,
                    borderColor: effectiveDisplayMode
                      ? colors.primary
                      : colors.border,
                  },
                ]}
                onPress={() => setIsDisplayMode((prev) => !prev)}
                activeOpacity={0.7}
                accessibilityLabel={effectiveDisplayMode ? "编辑" : "完成"}
              >
                <Ionicons
                  name={
                    effectiveDisplayMode
                      ? "create-outline"
                      : "checkmark-outline"
                  }
                  size={16}
                  color={
                    effectiveDisplayMode ? colors.primary : colors.foreground
                  }
                />
                <Text
                  style={[
                    styles.headerCenterText,
                    {
                      color: effectiveDisplayMode
                        ? colors.primary
                        : colors.foreground,
                    },
                  ]}
                >
                  {effectiveDisplayMode ? "编辑" : "完成"}
                </Text>
              </TouchableOpacity>
            </View>
          ) : null}

          <TouchableOpacity
            style={[
              styles.headerBtn,
              {
                borderColor: colors.border,
                backgroundColor: colors.surface,
              },
            ]}
            onPress={() => setMenuVisible(true)}
            activeOpacity={0.7}
            accessibilityLabel="菜单"
          >
            <Ionicons name="menu-outline" size={18} color={colors.foreground} />
          </TouchableOpacity>
        </View>

        <View style={styles.main}>
          <OcrSection
            ref={ocrRef}
            ocrUnlocked={ocrUnlocked}
            onOcrResult={handleOcrResult}
            onUnlockOcr={handleUnlockOcr}
            hideActions
          />

          <WordInputSection
            value={wordInput}
            onChange={setWordInput}
            onSetSample={() => setWordInput(SAMPLE_WORDS)}
            onClear={() => setWordInput("")}
            startIndex={startIndex}
            onStartIndexChange={setStartIndex}
            isDisplayMode={isDisplayMode}
          />
        </View>

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

        <Modal
          visible={menuVisible}
          transparent
          animationType="fade"
          onRequestClose={closeMenu}
        >
          <Pressable style={styles.menuBackdrop} onPress={closeMenu}>
            <Pressable
              style={[
                styles.menuPanel,
                {
                  backgroundColor: colors.background,
                  borderColor: colors.border,
                  marginTop: insets.top + spacing.sm + 36,
                  marginRight: spacing.lg,
                },
              ]}
              onPress={() => {}}
            >
              {menuItems.map((item) => (
                <TouchableOpacity
                  key={item.key}
                  style={[
                    styles.menuItem,
                    item.accent && { backgroundColor: colors.primarySoft },
                  ]}
                  onPress={item.onPress}
                  disabled={item.disabled}
                  activeOpacity={0.7}
                >
                  <Ionicons
                    name={item.icon}
                    size={18}
                    color={item.accent ? colors.primary : colors.foreground}
                  />
                  <Text
                    style={[
                      styles.menuItemText,
                      {
                        color: item.accent ? colors.primary : colors.foreground,
                      },
                    ]}
                  >
                    {item.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </Pressable>
          </Pressable>
        </Modal>
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
    paddingTop: spacing.sm,
    paddingBottom: spacing.xs,
  },
  headerBtn: {
    width: 32,
    height: 32,
    borderRadius: radii.full,
    justifyContent: "center",
    alignItems: "center",
  },
  headerCenter: {
    position: "absolute",
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    justifyContent: "center",
    alignItems: "center",
  },
  headerCenterBtn: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.xs,
    height: 32,
    paddingHorizontal: spacing.md,
    borderRadius: radii.full,
    borderWidth: 1,
  },
  headerCenterText: {
    fontSize: 14,
    fontWeight: "600",
  },
  main: {
    flex: 1,
    minHeight: 0,
    gap: spacing.sm,
    width: "100%",
    alignSelf: "center",
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.sm,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  bottomPanel: {
    borderTopWidth: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
    width: "100%",
    alignSelf: "center",
  },
  menuBackdrop: {
    flex: 1,
    backgroundColor: "transparent",
    alignItems: "flex-end",
  },
  menuPanel: {
    minWidth: 168,
    borderRadius: radii.surface,
    borderWidth: 1,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.xs,
    shadowColor: "#000",
    shadowOpacity: 0.12,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 6,
  },
  menuItem: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    borderRadius: radii.control,
    marginHorizontal: spacing.xs,
  },
  menuItemText: {
    fontSize: 15,
    fontWeight: "600",
  },
});
