import { useCallback, useEffect, useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { OcrSection } from "../components/OcrSection";
import { PlaybackControls } from "../components/PlaybackControls";
import { ProgressCard } from "../components/ProgressCard";
import { Toast } from "../components/Toast";
import { WordInputSection } from "../components/WordInputSection";
import { WrongWordsPanel } from "../components/WrongWordsPanel";
import { usePlayback } from "../hooks/usePlayback";
import { useToast } from "../hooks/useToast";
import { useWrongWords } from "../hooks/useWrongWords";
import {
  DEFAULT_TTS_VOICE,
  loadPersistedVoice,
  parseWords,
  saveTtsVoice,
} from "../lib/dictation";
import { colors } from "../lib/designTokens";
import {
  loadPersistedWrongWords,
  loadWordInput,
  saveWordInput,
} from "../lib/storage";

const SAMPLE_WORDS = "apple banana cat dog elephant fish grape";

export function HomeScreen() {
  const [ready, setReady] = useState(false);
  const [wordInput, setWordInput] = useState("");
  const [intervalSec, setIntervalSec] = useState(8);
  const [autoNext, setAutoNext] = useState(true);
  const [voice, setVoice] = useState(DEFAULT_TTS_VOICE);
  const [showWord, setShowWord] = useState(false);

  const { toast, showToast } = useToast();
  const { wrongWords, markedFlash, markWrong, exportWrong, clearWrong, removeWrongWord } =
    useWrongWords();
  const playback = usePlayback({ intervalSec, autoNext, voice });

  // Load persisted data on mount
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

  // Persist word input changes
  useEffect(() => {
    if (ready) saveWordInput(wordInput);
  }, [wordInput, ready]);

  const handleVoiceChange = useCallback((next: string) => {
    setVoice(next);
    saveTtsVoice(next);
  }, []);

  const handleOcrResult = useCallback(
    (words: string[]) => {
      setWordInput(words.join("\n"));
    },
    [],
  );

  const handleMarkWrong = useCallback(() => {
    if (!playback.isActive || playback.currentIndex >= playback.wordList.length) return;
    markWrong(playback.wordList[playback.currentIndex]!);
  }, [playback.isActive, playback.currentIndex, playback.wordList, markWrong]);

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

  const handleExportWrong = useCallback(async () => {
    const msg = await exportWrong();
    if (msg) showToast(msg);
  }, [exportWrong, showToast]);

  const handleClearWrong = useCallback(() => {
    if (wrongWords.length === 0) return;
    clearWrong();
    showToast("已清空错词本");
  }, [wrongWords, clearWrong, showToast]);

  if (!ready) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  const isActive = playback.isActive;
  const showInputSection = !isActive || showWord;

  return (
    <SafeAreaView style={styles.safeArea} edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <ScrollView
          style={styles.scroll}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
        >
          {!isActive && (
            <OcrSection wordInput={wordInput} onOcrResult={handleOcrResult} />
          )}

          {showInputSection && (
            <WordInputSection
              value={wordInput}
              disabled={isActive}
              onChange={setWordInput}
              onSetSample={() => setWordInput(SAMPLE_WORDS)}
              onClear={() => setWordInput("")}
            />
          )}

          <ProgressCard
            wordList={playback.wordList}
            currentIndex={playback.currentIndex}
            playState={playback.playState}
            showWord={showWord}
            onToggleShowWord={() => setShowWord((v) => !v)}
            markedFlash={markedFlash}
            wrongWords={wrongWords}
          />

          <PlaybackControls
            playState={playback.playState}
            intervalSec={intervalSec}
            autoNext={autoNext}
            voice={voice}
            remainingMs={playback.remainingMs}
            currentIndex={playback.currentIndex}
            wordList={playback.wordList}
            onIntervalChange={setIntervalSec}
            onAutoNextChange={setAutoNext}
            onVoiceChange={handleVoiceChange}
            onPlayToggle={handlePlayToggle}
            onStop={playback.stopDictation}
            onSkipNext={playback.skipToNextWord}
            onMarkWrong={handleMarkWrong}
          />

          <WrongWordsPanel
            wrongWords={wrongWords}
            onExport={handleExportWrong}
            onClear={handleClearWrong}
            onRemove={removeWrongWord}
          />
        </ScrollView>

        <Toast message={toast} />
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    flex: 1,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
    paddingTop: 16,
    gap: 16,
    paddingBottom: 40,
  },
  loadingContainer: {
    flex: 1,
    backgroundColor: colors.surface,
    justifyContent: "center",
    alignItems: "center",
  },
});
