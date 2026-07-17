import { Ionicons } from "@expo/vector-icons";
import { LinearGradient } from "expo-linear-gradient";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  TouchableOpacity,
  Text,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { BottomSheet } from "../components/BottomSheet";
import { Button, IconButton } from "../components/Button";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { HistoryDrawer } from "../components/HistoryDrawer";
import { LibraryDrawer } from "../components/LibraryDrawer";
import { OcrSection, type OcrSectionHandle } from "../components/OcrSection";
import { PlaybackControls } from "../components/PlaybackControls";
import { Toast } from "../components/Toast";
import { WordInputSection } from "../components/WordInputSection";
import { useToast } from "../hooks/useToast";
import { parseWords } from "../lib/dictation";
import { enrichWordListText } from "../lib/dictionary";
import { fonts, radii, spacing } from "../lib/designTokens";
import { OCR_UI_IDLE, type OcrUiState } from "../lib/ocr";
import {
  addWordHistory,
  clearWordHistory,
  deleteWordHistory,
  getLibraryGroups,
  loadPersistedWrongWords,
  loadWordHistory,
  loadWordInput,
  saveWordInput,
  type LibraryGroup,
  WordHistoryEntry,
} from "../lib/storage";
import { useThemeColors, useThemeMode } from "../lib/theme";
import type { RootStackParamList } from "../navigation/types";

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
  const colors = useThemeColors();
  const { mode, toggleTheme } = useThemeMode();
  const [ready, setReady] = useState(false);
  const [wordInput, setWordInput] = useState("");
  const [intervalSec, setIntervalSec] = useState(4.5);
  const [autoNext, setAutoNext] = useState(true);
  const [startIndex, setStartIndex] = useState(0);
  const [shuffle, setShuffle] = useState(false);
  const [isDisplayMode, setIsDisplayMode] = useState(true);
  const [ocrUi, setOcrUi] = useState<OcrUiState>(OCR_UI_IDLE);
  const [history, setHistory] = useState<WordHistoryEntry[]>([]);
  const [historyDrawerVisible, setHistoryDrawerVisible] = useState(false);
  const [libraryDrawerVisible, setLibraryDrawerVisible] = useState(false);
  const [menuVisible, setMenuVisible] = useState(false);
  const [cameraSheetVisible, setCameraSheetVisible] = useState(false);
  const libraryGroups = useMemo<LibraryGroup[]>(() => getLibraryGroups(), []);
  const ocrRef = useRef<OcrSectionHandle>(null);
  // Edge-to-edge Android ignores adjustResize; pad manually when keyboard opens.
  const [androidKeyboardHeight, setAndroidKeyboardHeight] = useState(0);

  useEffect(() => {
    if (Platform.OS !== "android") return;

    const showSub = Keyboard.addListener("keyboardDidShow", (e) => {
      setAndroidKeyboardHeight(e.endCoordinates.height);
    });
    const hideSub = Keyboard.addListener("keyboardDidHide", () => {
      setAndroidKeyboardHeight(0);
    });

    return () => {
      showSub.remove();
      hideSub.remove();
    };
  }, []);

  const androidKeyboardOpen = androidKeyboardHeight > 0;

  // Confirm dialog state
  const [dialog, setDialog] = useState<{
    visible: boolean;
    title: string;
    message: string;
    confirmLabel: string;
    action: () => void;
  } | null>(null);

  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const { toast, showToast, hideToast } = useToast();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [savedInput, , savedHistory] = await Promise.all([
        loadWordInput(),
        loadPersistedWrongWords(),
        loadWordHistory(),
      ]);
      if (cancelled) return;
      if (savedInput) setWordInput(enrichWordListText(savedInput));
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
    // OCR returns bare words; enrich immediately so display mode shows meta.
    setWordInput(enrichWordListText(words.join("\n")));
    setIsDisplayMode(true);
  }, []);

  const handleToggleDisplayMode = useCallback(() => {
    setIsDisplayMode((prev) => {
      const next = !prev;
      // Leaving edit mode ("完成"): fill in offline POS + meaning.
      if (next) setWordInput((text) => enrichWordListText(text));
      return next;
    });
  }, []);

  const handleStart = useCallback(() => {
    // Ensure enrichment even if the user starts from edit mode.
    const enriched = enrichWordListText(wordInput);
    if (enriched !== wordInput) setWordInput(enriched);

    const allWords = parseWords(enriched);
    if (allWords.length === 0) {
      showToast("请先输入单词列表");
      return;
    }
    const clampedStart = Math.min(startIndex, allWords.length - 1);
    let words = allWords.slice(clampedStart);
    if (shuffle) {
      words = shuffleArray(words);
    }
    addWordHistory(enriched).then(() => loadWordHistory().then(setHistory));
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
    (entry: WordHistoryEntry) => {
      const text = entry.enrichedText ?? entry.text;
      setWordInput(enrichWordListText(text));
      setIsDisplayMode(true);
      showToast("已载入历史记录");
    },
    [showToast],
  );

  const handleApplyLibrary = useCallback(
    (entry: WordHistoryEntry) => {
      const text = entry.enrichedText ?? entry.text;
      setWordInput(enrichWordListText(text));
      setIsDisplayMode(true);
      showToast("已载入词库");
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
    if (history.length === 0) return;
    setDialog({
      visible: true,
      title: "清空历史",
      message: "确定要清空历史记录吗？",
      confirmLabel: "清空",
      action: () => {
        clearWordHistory().then(() => loadWordHistory().then(setHistory));
      },
    });
  }, [history]);

  const parsedWordCount = wordCount(wordInput);
  const canToggleDisplayMode = parsedWordCount > 0;
  const effectiveDisplayMode = isDisplayMode && canToggleDisplayMode;
  const showOcrProgress = ocrUi.busy && Boolean(ocrUi.message);

  const closeMenu = useCallback(() => setMenuVisible(false), []);
  const closeCameraSheet = useCallback(() => setCameraSheetVisible(false), []);

  const runSheetAction = useCallback((close: () => void, action: () => void) => {
    close();
    // Android Dialog teardown needs a beat before presenting another Modal;
    // a single rAF is often too early on real devices and leaves the sheet
    // stuck mid-open.
    const delayMs = Platform.OS === "android" ? 320 : 0;
    if (delayMs === 0) {
      requestAnimationFrame(action);
    } else {
      setTimeout(action, delayMs);
    }
  }, []);

  const menuItems: MenuItem[] = [
    {
      key: "history",
      icon: "time-outline",
      label: "历史记录",
      onPress: () =>
        runSheetAction(closeMenu, () => setHistoryDrawerVisible(true)),
    },
    {
      key: "library",
      icon: "library-outline",
      label: "词库",
      onPress: () =>
        runSheetAction(closeMenu, () => setLibraryDrawerVisible(true)),
    },
    {
      key: "settings",
      icon: "settings-outline",
      label: "设置",
      onPress: () =>
        runSheetAction(closeMenu, () => navigation.navigate("Settings")),
    },
  ];

  const cameraItems: MenuItem[] = [
    {
      key: "photo",
      icon: "camera-outline",
      label: "拍摄照片",
      onPress: () =>
        runSheetAction(closeCameraSheet, () => ocrRef.current?.processPhoto()),
    },
    {
      key: "album",
      icon: "images-outline",
      label: "从相册选取",
      onPress: () =>
        runSheetAction(closeCameraSheet, () => ocrRef.current?.processAlbum()),
    },
  ];

  const renderSheetRow = (item: MenuItem) => (
    <TouchableOpacity
      key={item.key}
      style={[
        styles.sheetRow,
        {
          backgroundColor: colors.surface,
          borderColor: colors.borderSubtle,
        },
      ]}
      onPress={item.onPress}
      disabled={item.disabled}
      activeOpacity={0.7}
      accessibilityRole="button"
      accessibilityLabel={item.label}
    >
      <Ionicons name={item.icon} size={20} color={colors.foreground} />
      <Text style={[styles.sheetRowText, { color: colors.foreground }]}>
        {item.label}
      </Text>
      <Ionicons
        name="chevron-forward"
        size={16}
        color={colors.subtle}
        style={styles.sheetRowChevron}
      />
    </TouchableOpacity>
  );

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
      edges={
        androidKeyboardOpen
          ? ["top", "left", "right"]
          : ["top", "bottom", "left", "right"]
      }
    >
      <LinearGradient
        colors={[colors.goldSoft, "transparent"]}
        style={styles.heroGlow}
        pointerEvents="none"
      />
      <KeyboardAvoidingView
        style={[
          styles.container,
          androidKeyboardOpen && { paddingBottom: androidKeyboardHeight },
        ]}
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <View style={styles.header}>
          <View style={styles.headerBrand}>
            <Ionicons name="time-outline" size={26} color={colors.gold} />
            <Text style={[styles.brandAlice, { color: colors.foreground }]}>
              Alice
            </Text>
            <Text style={[styles.brandDictation, { color: colors.rose }]}>
              听写
            </Text>
          </View>

          {showOcrProgress ? (
            <View
              style={[
                styles.ocrProgressPill,
                {
                  backgroundColor: colors.primarySoft,
                  borderColor: colors.primary,
                },
              ]}
              accessibilityLabel={ocrUi.message}
            >
              <ActivityIndicator size="small" color={colors.primary} />
              <Text
                style={[styles.ocrProgressText, { color: colors.primary }]}
                numberOfLines={1}
                ellipsizeMode="tail"
              >
                {ocrUi.message}
              </Text>
            </View>
          ) : null}

          <IconButton
            icon="menu-outline"
            onPress={() => setMenuVisible(true)}
            accessibilityLabel="菜单"
          />
        </View>

        <View style={styles.main}>
          <OcrSection
            ref={ocrRef}
            onOcrResult={handleOcrResult}
            onOcrStateChange={setOcrUi}
            onOcrOutcome={showToast}
            hideActions
          />

          <View style={styles.sectionHeader}>
            <View style={styles.sectionTitleRow}>
              <Text style={[styles.sectionTitle, { color: colors.foreground }]}>
                单词列表
              </Text>
              {parsedWordCount > 0 ? (
                <View
                  style={[
                    styles.countBadge,
                    {
                      backgroundColor: colors.surface,
                      borderColor: colors.border,
                    },
                  ]}
                >
                  <Text style={[styles.countBadgeText, { color: colors.muted }]}>
                    {parsedWordCount} 词
                  </Text>
                </View>
              ) : null}
            </View>
            {canToggleDisplayMode ? (
              <Button
                label={effectiveDisplayMode ? "编辑" : "完成"}
                icon={
                  effectiveDisplayMode ? "create-outline" : "checkmark-outline"
                }
                variant="outline"
                size="sm"
                active={!effectiveDisplayMode}
                onPress={handleToggleDisplayMode}
              />
            ) : null}
          </View>

          <WordInputSection
            value={wordInput}
            onChange={setWordInput}
            onSetSample={() => setWordInput(SAMPLE_WORDS)}
            onClear={() => setWordInput("")}
            startIndex={startIndex}
            onStartIndexChange={setStartIndex}
            isDisplayMode={isDisplayMode}
          />

          {!androidKeyboardOpen ? (
            <IconButton
              icon="camera"
              size={56}
              variant="gold"
              onPress={() => setCameraSheetVisible(true)}
              accessibilityLabel="拍照识词"
              style={[
                styles.cameraFab,
                // Keep clear of the edit-mode footer (示例/清空 row).
                !effectiveDisplayMode && styles.cameraFabRaised,
              ]}
            />
          ) : null}
        </View>

        {!androidKeyboardOpen ? (
          <View style={[styles.bottomPanel, { borderTopColor: colors.border }]}>
            <PlaybackControls
              intervalSec={intervalSec}
              autoNext={autoNext}
              onIntervalChange={setIntervalSec}
              onAutoNextChange={setAutoNext}
              onPlayToggle={handleStart}
              shuffle={shuffle}
              onShuffleChange={setShuffle}
              wordCount={parsedWordCount}
            />
          </View>
        ) : null}
        <Toast toast={toast} onActionPress={hideToast} />
        <HistoryDrawer
          visible={historyDrawerVisible}
          history={history}
          onClose={() => setHistoryDrawerVisible(false)}
          onApply={handleApplyHistory}
          onDelete={handleDeleteHistory}
          onClear={handleClearHistory}
        />
        <LibraryDrawer
          visible={libraryDrawerVisible}
          groups={libraryGroups}
          onClose={() => setLibraryDrawerVisible(false)}
          onApply={handleApplyLibrary}
        />

        <BottomSheet visible={menuVisible} onClose={closeMenu} title="更多">
          <View style={styles.sheetList}>{menuItems.map(renderSheetRow)}</View>
        </BottomSheet>

        <BottomSheet
          visible={cameraSheetVisible}
          onClose={closeCameraSheet}
          title="拍照识词"
        >
          <View style={styles.sheetList}>{cameraItems.map(renderSheetRow)}</View>
        </BottomSheet>
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
  heroGlow: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    height: 180,
    opacity: 0.55,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  headerBrand: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.xs,
  },
  brandAlice: {
    fontFamily: fonts.display,
    fontStyle: "italic",
    fontSize: 24,
    fontWeight: "700",
    letterSpacing: 0.3,
  },
  brandDictation: {
    fontFamily: fonts.display,
    fontSize: 24,
    fontWeight: "700",
    letterSpacing: 0.3,
  },
  ocrProgressPill: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.xs,
    height: 32,
    paddingHorizontal: spacing.md,
    borderRadius: radii.full,
    borderWidth: 1,
    maxWidth: "80%",
  },
  ocrProgressText: {
    fontSize: 13,
    fontWeight: "600",
    flexShrink: 1,
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
  sectionHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingVertical: spacing.xs,
  },
  sectionTitle: {
    fontFamily: fonts.display,
    fontSize: 17,
    fontWeight: "700",
    letterSpacing: 0.3,
  },
  sectionTitleRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
  },
  countBadge: {
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: radii.full,
    borderWidth: 1,
  },
  countBadgeText: {
    fontSize: 11,
    fontWeight: "600",
    fontVariant: ["tabular-nums"],
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
  sheetList: {
    gap: spacing.sm,
    paddingBottom: spacing.sm,
  },
  sheetRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    minHeight: 52,
    borderRadius: radii.surface,
    borderWidth: 1,
  },
  sheetRowText: {
    fontSize: 15,
    fontWeight: "600",
  },
  sheetRowChevron: {
    marginLeft: "auto",
  },
  cameraFab: {
    position: "absolute",
    right: spacing.lg,
    bottom: spacing.md,
  },
  cameraFabRaised: {
    bottom: spacing.md + 40,
  },
});
