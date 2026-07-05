import { useCallback, useEffect, useState } from "react";
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
} from "../lib/storage";
import { radii, spacing } from "../lib/designTokens";
import { useThemeColors, useThemeMode } from "../lib/theme";

const SAMPLE_WORDS = "apple banana cat dog elephant fish grape";

type HomeNavigation = NativeStackNavigationProp<RootStackParamList, "Home">;

export function HomeScreen() {
  const navigation = useNavigation<HomeNavigation>();
  const colors = useThemeColors();
  const { mode, toggleTheme } = useThemeMode();
  const [ready, setReady] = useState(false);
  const [wordInput, setWordInput] = useState("");
  const [intervalSec, setIntervalSec] = useState(4.5);
  const [autoNext, setAutoNext] = useState(true);

  const { toast, showToast } = useToast();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [savedInput] = await Promise.all([
        loadWordInput(),
        loadPersistedWrongWords(),
      ]);
      if (cancelled) return;
      if (savedInput) setWordInput(savedInput);
      setReady(true);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (ready) saveWordInput(wordInput);
  }, [wordInput, ready]);

  const handleOcrResult = useCallback((words: string[]) => {
    setWordInput(words.join("\n"));
  }, []);

  const handleStart = useCallback(() => {
    const words = parseWords(wordInput);
    if (words.length === 0) {
      showToast("请先输入单词列表");
      return;
    }
    navigation.navigate("Dictation", {
      words,
      intervalSec,
      autoNext,
    });
  }, [autoNext, intervalSec, navigation, showToast, wordInput]);

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
            <Text style={styles.themeBtnText}>
              {mode === "dark" ? "☀️" : "🌙"}
            </Text>
          </TouchableOpacity>
        </View>

        <ScrollView
          style={styles.scroll}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.content}>
            <OcrSection wordInput={wordInput} onOcrResult={handleOcrResult} />
            <WordInputSection
              value={wordInput}
              onChange={setWordInput}
              onSetSample={() => setWordInput(SAMPLE_WORDS)}
              onClear={() => setWordInput("")}
            />
          </View>
        </ScrollView>

        <View
          style={[styles.bottomPanel, { borderTopColor: colors.border }]}
        >
          <PlaybackControls
            intervalSec={intervalSec}
            autoNext={autoNext}
            onIntervalChange={setIntervalSec}
            onAutoNextChange={setAutoNext}
            onPlayToggle={handleStart}
          />
        </View>
        <Toast message={toast} />
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
  themeBtnText: {
    fontSize: 18,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.sm,
    paddingBottom: spacing.md,
  },
  content: {
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
});
