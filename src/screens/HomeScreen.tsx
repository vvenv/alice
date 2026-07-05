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
import { SafeAreaView } from "react-native-safe-area-context";

import { OcrSection } from "../components/OcrSection";
import { PlaybackControls } from "../components/PlaybackControls";
import { Toast } from "../components/Toast";
import { WordInputSection } from "../components/WordInputSection";
import { usePlayback } from "../hooks/usePlayback";
import { useToast } from "../hooks/useToast";
import {
  DEFAULT_TTS_VOICE,
  loadPersistedVoice,
  parseWords,
  saveTtsVoice,
} from "../lib/dictation";
import {
  loadPersistedWrongWords,
  loadWordInput,
  saveWordInput,
} from "../lib/storage";
import { useThemeColors, useThemeMode } from "../lib/theme";

const SAMPLE_WORDS = "apple banana cat dog elephant fish grape";

export function HomeScreen() {
  const colors = useThemeColors();
  const { mode, toggleTheme } = useThemeMode();
  const [ready, setReady] = useState(false);
  const [wordInput, setWordInput] = useState("");
  const [intervalSec, setIntervalSec] = useState(4.5);
  const [autoNext, setAutoNext] = useState(true);
  const [voice, setVoice] = useState(DEFAULT_TTS_VOICE);

  const { toast, showToast } = useToast();
  const playback = usePlayback({ intervalSec, autoNext, voice });

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [savedInput, savedVoice] = await Promise.all([
        loadWordInput(),
        loadPersistedVoice(),
        loadPersistedWrongWords(),
      ]);
      if (cancelled) return;
      if (savedInput) setWordInput(savedInput);
      setVoice(savedVoice);
      setReady(true);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (ready) saveWordInput(wordInput);
  }, [wordInput, ready]);

  const handleVoiceChange = useCallback((next: string) => {
    setVoice(next);
    saveTtsVoice(next);
  }, []);

  const handleOcrResult = useCallback((words: string[]) => {
    setWordInput(words.join("\n"));
  }, []);

  const handlePlayToggle = useCallback(() => {
    if (playback.playState === "idle") {
      const words = parseWords(wordInput);
      if (words.length === 0) {
        showToast("请先输入单词列表");
        return;
      }
      playback.startDictation(words);
      return;
    }
    if (playback.playState === "playing") {
      playback.pauseDictation();
      return;
    }
    playback.resumeDictation();
  }, [playback, showToast, wordInput]);

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
        {/* Theme toggle */}
        <View style={styles.topBar}>
          <Text style={[styles.title, { color: colors.foreground }]}>Alice Dictation</Text>
          <TouchableOpacity
            style={[styles.themeBtn, { borderColor: colors.border }]}
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
        >
          <OcrSection wordInput={wordInput} onOcrResult={handleOcrResult} />

          <View style={styles.wordInputWrapper}>
            <WordInputSection
              value={wordInput}
              onChange={setWordInput}
              onSetSample={() => setWordInput(SAMPLE_WORDS)}
              onClear={() => setWordInput("")}
            />
          </View>
        </ScrollView>

        <View style={styles.playbackControls}>
          <PlaybackControls
            intervalSec={intervalSec}
            autoNext={autoNext}
            voice={voice}
            onIntervalChange={setIntervalSec}
            onAutoNextChange={setAutoNext}
            onVoiceChange={handleVoiceChange}
            onPlayToggle={handlePlayToggle}
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
  topBar: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 8,
  },
  title: {
    fontSize: 24,
    fontWeight: "bold",
  },
  themeBtn: {
    width: 24,
    height: 24,
    justifyContent: "center",
    alignItems: "center",
  },
  themeBtnText: {
    fontSize: 24,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: 16,
    paddingVertical: 16,
    gap: 16,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  playbackControls: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  wordInputWrapper: {
    flex: 1,
  },
});
