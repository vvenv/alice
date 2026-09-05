import { Ionicons } from "@expo/vector-icons";
import { LinearGradient } from "expo-linear-gradient";
import { useFocusEffect, useNavigation } from "@react-navigation/native";
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
import { FavoritesDrawer } from "../components/FavoritesDrawer";
import { HistoryDrawer } from "../components/HistoryDrawer";
import { LibraryDrawer } from "../components/LibraryDrawer";
import { OcrSection, type OcrSectionHandle } from "../components/OcrSection";
import { PlaybackControls } from "../components/PlaybackControls";
import { RechargeModal } from "../components/RechargeModal";
import { Toast } from "../components/Toast";
import { WordInputSection } from "../components/WordInputSection";
import { useOcrQuota } from "../hooks/useOcrQuota";
import { useToast } from "../hooks/useToast";
import { parseWords } from "../lib/dictation";
import { enrichWordListText } from "../lib/dictionary";
import { fonts, radii, spacing } from "../lib/designTokens";
import { BUILTIN_MODELS, type CreditPack } from "../lib/credits";
import { OCR_DISCLAIMER, OCR_UI_IDLE, type OcrUiState } from "../lib/ocr";
import {
  addWordHistory,
  clearWordHistory,
  DEFAULT_INTERVAL_SEC,
  deleteWordHistory,
  getLibraryGroups,
  loadFavorites,
  loadIntervalSec,
  loadPersistedFavorites,
  loadPersistedWrongWords,
  loadWordHistory,
  loadWordInput,
  saveIntervalSec,
  saveWordInput,
  toggleFavorite,
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
  const [intervalSec, setIntervalSec] = useState(DEFAULT_INTERVAL_SEC);
  const [autoNext, setAutoNext] = useState(true);
  const [startIndex, setStartIndex] = useState(0);
  const [shuffle, setShuffle] = useState(false);
  const [isDisplayMode, setIsDisplayMode] = useState(true);
  const [ocrUi, setOcrUi] = useState<OcrUiState>(OCR_UI_IDLE);
  const [history, setHistory] = useState<WordHistoryEntry[]>([]);
  const [favorites, setFavorites] = useState<string[]>([]);
  const [historyDrawerVisible, setHistoryDrawerVisible] = useState(false);
  const [libraryDrawerVisible, setLibraryDrawerVisible] = useState(false);
  const [favoritesDrawerVisible, setFavoritesDrawerVisible] = useState(false);
  const [menuVisible, setMenuVisible] = useState(false);
  const [cameraSheetVisible, setCameraSheetVisible] = useState(false);
  const [rechargeVisible, setRechargeVisible] = useState(false);
  const quota = useOcrQuota();
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
  // Latest input for the unmount flush below (that effect runs once, so a
  // captured closure would go stale).
  const wordInputRef = useRef(wordInput);
  wordInputRef.current = wordInput;

  const { toast, showToast, hideToast } = useToast();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [savedInput, , savedHistory, savedFavorites, savedInterval] =
        await Promise.all([
          loadWordInput(),
          loadPersistedWrongWords(),
          loadWordHistory(),
          loadPersistedFavorites(),
          loadIntervalSec(),
        ]);
      if (cancelled) return;
      if (savedInput) setWordInput(enrichWordListText(savedInput));
      setHistory(savedHistory);
      setFavorites(savedFavorites);
      setIntervalSec(savedInterval);
      setReady(true);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useFocusEffect(
    useCallback(() => {
      if (!ready) return;
      let cancelled = false;
      loadIntervalSec().then((sec) => {
        if (!cancelled) setIntervalSec(sec);
      });
      return () => {
        cancelled = true;
      };
    }, [ready]),
  );

  // Debounced persistence to avoid writing AsyncStorage on every keystroke
  useEffect(() => {
    if (!ready) return;
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      debounceRef.current = null;
      saveWordInput(wordInput);
      // In display mode the input is considered finalised — sync it to
      // history immediately so the user doesn't have to start dictation.
      if (isDisplayMode) {
        const enriched = enrichWordListText(wordInput);
        if (parseWords(enriched).length > 0) {
          addWordHistory(enriched).then(() =>
            loadWordHistory().then(setHistory),
          );
        }
      }
    }, WORD_INPUT_SAVE_DEBOUNCE_MS);
    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
        debounceRef.current = null;
      }
    };
  }, [wordInput, ready, isDisplayMode]);

  // Always persist the latest input on unmount. The debounce effect's
  // cleanup cancels the timer (including on unmount, depending on
  // declaration order); this write does not rely on that timer still
  // being pending.
  useEffect(
    () => () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
        debounceRef.current = null;
      }
      saveWordInput(wordInputRef.current);
    },
    [],
  );

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
    // A premium recognition may have just consumed credits — sync the balance.
    quota.syncFromCache();
  }, [quota]);

  const handleRecharge = useCallback(
    async (pack: CreditPack) => {
      await quota.recharge(pack);
      showToast(`充值成功 +${pack.credits + pack.bonus} credits`);
    },
    [quota, showToast],
  );

  const handleToggleDisplayMode = useCallback(() => {
    setIsDisplayMode((prev) => {
      const next = !prev;
      // Leaving edit mode ("完成"): fill in offline POS + meaning.
      if (next) setWordInput((text) => enrichWordListText(text));
      return next;
    });
  }, []);

  const handleIntervalChange = useCallback((sec: number) => {
    setIntervalSec(sec);
    saveIntervalSec(sec).catch(() => {});
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

  const handleApplyFavorite = useCallback(
    (entry: WordHistoryEntry) => {
      const text = entry.enrichedText ?? entry.text;
      setWordInput(enrichWordListText(text));
      setIsDisplayMode(true);
      showToast("已载入收藏");
    },
    [showToast],
  );

  const handleToggleFavorite = useCallback((id: string) => {
    toggleFavorite(id).then(() => setFavorites(loadFavorites()));
  }, []);

  const handleDeleteHistory = useCallback((id: string) => {
    setDialog({
      visible: true,
      title: "删除记录",
      message: "确定要删除这条历史记录吗？",
      confirmLabel: "删除",
      action: () => {
        setHistory((prev) => prev.filter((e) => e.id !== id));
        // deleteWordHistory also drops the favorite if present.
        deleteWordHistory(id).then(() => setFavorites(loadFavorites()));
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
        clearWordHistory().then(() => {
          loadWordHistory().then(setHistory);
          setFavorites(loadFavorites());
        });
      },
    });
  }, [history]);

  const parsedWordCount = wordCount(wordInput);
  const canToggleDisplayMode = parsedWordCount > 0;
  const effectiveDisplayMode = isDisplayMode && canToggleDisplayMode;
  const showOcrProgress = ocrUi.busy && Boolean(ocrUi.message);

  const closeMenu = useCallback(() => setMenuVisible(false), []);
  const closeCameraSheet = useCallback(() => setCameraSheetVisible(false), []);

  const runSheetAction = useCallback(
    (close: () => void, action: () => void) => {
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
    },
    [],
  );

  const menuItems: MenuItem[] = [
    {
      key: "favorites",
      icon: "star-outline",
      label: "收藏",
      onPress: () =>
        runSheetAction(closeMenu, () => setFavoritesDrawerVisible(true)),
    },
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
            onInsufficientCredits={() => setRechargeVisible(true)}
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
                  <Text
                    style={[styles.countBadgeText, { color: colors.muted }]}
                  >
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
              onIntervalChange={handleIntervalChange}
              onAutoNextChange={setAutoNext}
              onPlayToggle={handleStart}
              shuffle={shuffle}
              onShuffleChange={setShuffle}
              wordCount={parsedWordCount}
            />
          </View>
        ) : null}
        <Toast toast={toast} onActionPress={hideToast} />
        <FavoritesDrawer
          visible={favoritesDrawerVisible}
          favorites={favorites}
          history={history}
          onClose={() => setFavoritesDrawerVisible(false)}
          onApply={handleApplyFavorite}
          onToggleFavorite={handleToggleFavorite}
        />
        <HistoryDrawer
          visible={historyDrawerVisible}
          history={history}
          favorites={favorites}
          onClose={() => setHistoryDrawerVisible(false)}
          onApply={handleApplyHistory}
          onDelete={handleDeleteHistory}
          onClear={handleClearHistory}
          onToggleFavorite={handleToggleFavorite}
        />
        <LibraryDrawer
          visible={libraryDrawerVisible}
          groups={libraryGroups}
          favorites={favorites}
          onClose={() => setLibraryDrawerVisible(false)}
          onApply={handleApplyLibrary}
          onToggleFavorite={handleToggleFavorite}
        />

        <BottomSheet visible={menuVisible} onClose={closeMenu} title="更多">
          <View style={styles.sheetList}>{menuItems.map(renderSheetRow)}</View>
        </BottomSheet>

        <BottomSheet
          visible={cameraSheetVisible}
          onClose={closeCameraSheet}
          title="拍照识词"
        >
          <View style={styles.ocrSheetBanner}>
            {quota.hasCustomConfig ? (
              <View
                style={[
                  styles.modelRow,
                  {
                    backgroundColor: colors.surface,
                    borderColor: colors.borderSubtle,
                  },
                ]}
              >
                <Ionicons
                  name="server-outline"
                  size={16}
                  color={colors.muted}
                />
                <Text
                  style={[styles.modelRowText, { color: colors.muted }]}
                  numberOfLines={1}
                >
                  使用自定义服务
                </Text>
                <TouchableOpacity
                  onPress={() =>
                    runSheetAction(closeCameraSheet, () =>
                      navigation.navigate("Settings"),
                    )
                  }
                  hitSlop={8}
                  activeOpacity={0.6}
                >
                  <Text
                    style={[styles.modelRowLink, { color: colors.primary }]}
                  >
                    设置
                  </Text>
                </TouchableOpacity>
              </View>
            ) : (
              <View style={styles.modelChips}>
                {BUILTIN_MODELS.map((m) => {
                  const active = quota.modelId === m.id;
                  return (
                    <TouchableOpacity
                      key={m.id}
                      style={[
                        styles.modelChip,
                        {
                          borderColor: active
                            ? colors.primary
                            : colors.borderSubtle,
                          backgroundColor: active
                            ? colors.primarySoft
                            : colors.surface,
                        },
                      ]}
                      onPress={() => quota.selectModel(m.id)}
                      activeOpacity={0.7}
                      accessibilityRole="radio"
                      accessibilityState={{ selected: active }}
                      accessibilityLabel={m.label}
                    >
                      <Text
                        style={[
                          styles.modelChipText,
                          {
                            color: active
                              ? colors.primary
                              : colors.foreground,
                          },
                        ]}
                      >
                        {m.label}
                      </Text>
                      {m.tier === "premium" ? (
                        <Text
                          style={[
                            styles.modelChipCost,
                            {
                              color: active ? colors.gold : colors.subtle,
                            },
                          ]}
                        >
                          {m.creditCost} credit
                        </Text>
                      ) : null}
                    </TouchableOpacity>
                  );
                })}
              </View>
            )}

            <View style={styles.creditsRow}>
              <Ionicons
                name="wallet-outline"
                size={14}
                color={colors.subtle}
              />
              <Text style={[styles.creditsText, { color: colors.muted }]}>
                Credits: {quota.credits}
              </Text>
              <TouchableOpacity
                onPress={() =>
                  runSheetAction(closeCameraSheet, () =>
                    setRechargeVisible(true),
                  )
                }
                hitSlop={8}
                activeOpacity={0.6}
                accessibilityRole="button"
                accessibilityLabel="充值"
              >
                <Text
                  style={[styles.creditsLink, { color: colors.primary }]}
                >
                  充值
                </Text>
              </TouchableOpacity>
            </View>

            <View
              style={[
                styles.ocrDisclaimer,
                { backgroundColor: colors.surface, borderColor: colors.borderSubtle },
              ]}
            >
              <Ionicons
                name="information-circle-outline"
                size={13}
                color={colors.subtle}
              />
              <Text
                style={[styles.ocrDisclaimerText, { color: colors.subtle }]}
              >
                {OCR_DISCLAIMER}
              </Text>
            </View>
          </View>

          <View style={styles.sheetList}>
            {cameraItems.map(renderSheetRow)}
          </View>
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
        <RechargeModal
          visible={rechargeVisible}
          credits={quota.credits}
          onClose={() => setRechargeVisible(false)}
          onPurchase={handleRecharge}
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
    pointerEvents: "none",
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
    width: "100%",
    maxWidth: 720,
    alignSelf: "center",
  },
  headerBrand: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.xs,
  },
  brandAlice: {
    fontFamily: fonts.displayItalic,
    fontSize: 24,
    letterSpacing: 0.3,
  },
  brandDictation: {
    fontFamily: fonts.displayZh,
    fontSize: 24,
    letterSpacing: 0.3,
  },
  ocrProgressPill: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.xs,
    minHeight: 32,
    paddingVertical: spacing.xs,
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
    maxWidth: 720,
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
    fontFamily: fonts.displayZh,
    fontSize: 17,
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
    paddingBottom: spacing.md,
    width: "100%",
    maxWidth: 720,
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
  ocrSheetBanner: {
    gap: spacing.sm,
    paddingBottom: spacing.sm,
  },
  modelRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.xs,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderRadius: radii.surface,
    borderWidth: 1,
  },
  modelRowText: {
    flex: 1,
    fontSize: 14,
    fontWeight: "600",
  },
  modelRowLink: {
    fontSize: 13,
    fontWeight: "700",
  },
  modelChips: {
    flexDirection: "row",
    gap: spacing.xs,
  },
  modelChip: {
    flex: 1,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.md,
    borderRadius: radii.control,
    borderWidth: 1.5,
    alignItems: "center",
    gap: 2,
  },
  modelChipText: {
    fontSize: 13,
    fontWeight: "600",
  },
  modelChipCost: {
    fontSize: 11,
    fontWeight: "600",
  },
  creditsRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.xs,
    paddingHorizontal: spacing.xs,
  },
  creditsText: {
    flex: 1,
    fontSize: 13,
    fontWeight: "600",
    fontVariant: ["tabular-nums"],
  },
  creditsLink: {
    fontSize: 13,
    fontWeight: "700",
  },
  ocrDisclaimer: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radii.control,
    borderWidth: StyleSheet.hairlineWidth,
  },
  ocrDisclaimerText: {
    fontSize: 11,
    flexShrink: 1,
  },
});
