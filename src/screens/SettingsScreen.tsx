import { Ionicons } from "@expo/vector-icons";
import { useFocusEffect, useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { useCallback, useEffect, useState } from "react";
import {
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import Constants from "expo-constants";

import { IconButton } from "../components/Button";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { OcrSettingsModal } from "../components/OcrSettingsModal";
import { RechargeModal } from "../components/RechargeModal";
import { Slider } from "../components/Slider";
import { Toast } from "../components/Toast";
import { TtsSettingsModal } from "../components/TtsSettingsModal";
import { useOcrQuota } from "../hooks/useOcrQuota";
import { useToast } from "../hooks/useToast";
import { getBuiltinModel, saveSelectedModelId, type CreditPack } from "../lib/credits";
import { loadSoundEnabled, setSoundEnabled } from "../lib/sound";
import { fonts, radii, spacing } from "../lib/designTokens";
import { OCR_DISCLAIMER } from "../lib/ocr";
import {
  DEFAULT_INTERVAL_SEC,
  DEFAULT_SPEECH_RATE,
  INTERVAL_STEP,
  MAX_INTERVAL_SEC,
  MAX_SPEECH_RATE,
  MIN_INTERVAL_SEC,
  MIN_SPEECH_RATE,
  loadIntervalSec,
  loadSpeechRate,
  saveIntervalSec,
  saveSpeechRate,
} from "../lib/storage";
import {
  loadReadTranslation,
  setReadTranslationEnabled,
  setSpeechRate,
} from "../lib/tts";
import {
  isCustomOcrConfigSet,
  loadOcrProviderConfig,
  requiresCustomOcrConfig,
  saveOcrProviderConfig,
  type OcrProviderConfig,
} from "../lib/ocrConfig";
import {
  isTtsProviderConfigSet,
  loadTtsSettings,
  saveTtsProviderConfig,
  saveTtsSource,
  type TtsProviderConfig,
  type TtsSource,
} from "../lib/ttsConfig";
import { useThemeColors, useThemeMode } from "../lib/theme";
import { clearTtsCache } from "../lib/tts";
import type { RootStackParamList } from "../navigation/types";

type SettingsNavigation = NativeStackNavigationProp<
  RootStackParamList,
  "Settings"
>;

type Section = {
  key: string;
  title: string;
  rows: Row[];
};

type Row = {
  key: string;
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  detail?: string;
  onPress?: () => void;
  destructive?: boolean;
};

export function SettingsScreen() {
  const navigation = useNavigation<SettingsNavigation>();
  const colors = useThemeColors();
  const { mode, setMode } = useThemeMode();
  const { toast, showToast, hideToast } = useToast();
  const [soundOn, setSoundOn] = useState(true);
  const [readTranslationOn, setReadTranslationOn] = useState(false);
  const [speechRate, setSpeechRateState] = useState(DEFAULT_SPEECH_RATE);
  const [intervalSec, setIntervalSec] = useState(DEFAULT_INTERVAL_SEC);
  const [ttsSource, setTtsSource] = useState<TtsSource>("youdao");
  const [ttsConfig, setTtsConfig] = useState<TtsProviderConfig | null>(null);
  const [ttsSettingsVisible, setTtsSettingsVisible] = useState(false);

  useEffect(() => {
    loadSoundEnabled().then(setSoundOn);
    loadReadTranslation().then(setReadTranslationOn);
    loadSpeechRate().then((rate) => {
      setSpeechRateState(rate);
      setSpeechRate(rate);
    });
    loadTtsSettings().then(({ source, config }) => {
      setTtsSource(source);
      setTtsConfig(config);
    });
  }, []);

  useFocusEffect(
    useCallback(() => {
      let cancelled = false;
      loadIntervalSec().then((sec) => {
        if (!cancelled) setIntervalSec(sec);
      });
      return () => {
        cancelled = true;
      };
    }, []),
  );

  const handleToggleSound = useCallback((value: boolean) => {
    setSoundOn(value);
    setSoundEnabled(value);
  }, []);

  const handleToggleReadTranslation = useCallback((value: boolean) => {
    setReadTranslationOn(value);
    setReadTranslationEnabled(value);
  }, []);

  const handleSpeechRateChange = useCallback((value: number) => {
    const rounded = Math.round(value * 10) / 10;
    setSpeechRateState(rounded);
    setSpeechRate(rounded);
    saveSpeechRate(rounded).catch(() => {});
  }, []);

  const handleIntervalChange = useCallback((value: number) => {
    setIntervalSec(value);
    saveIntervalSec(value).catch(() => {});
  }, []);

  const handleSelectTtsSource = useCallback((source: TtsSource) => {
    setTtsSource(source);
    saveTtsSource(source).catch(() => {});
    setTtsSettingsVisible(false);
    showToast(
      source === "custom" ? "已切换到自定义发音服务" : "已恢复有道词典发音",
    );
  }, [showToast]);

  const handleSaveTtsConfig = useCallback(
    (cfg: TtsProviderConfig | null) => {
      setTtsConfig(cfg);
      saveTtsProviderConfig(cfg).catch(() => {});
      if (cfg) {
        setTtsSource("custom");
        saveTtsSource("custom").catch(() => {});
        showToast("已启用自定义发音服务");
      } else {
        setTtsSource("youdao");
        saveTtsSource("youdao").catch(() => {});
        showToast("已清除自定义发音配置");
      }
      setTtsSettingsVisible(false);
    },
    [showToast],
  );

  const [customOcrConfig, setCustomOcrConfig] =
    useState<OcrProviderConfig | null>(null);
  const [ocrSettingsVisible, setOcrSettingsVisible] = useState(false);
  const [rechargeVisible, setRechargeVisible] = useState(false);
  const quota = useOcrQuota();
  const [dialog, setDialog] = useState<{
    visible: boolean;
    title: string;
    message: string;
    confirmLabel: string;
    action: () => void;
  } | null>(null);

  useEffect(() => {
    loadOcrProviderConfig().then(setCustomOcrConfig);
  }, []);

  const handleSaveOcrConfig = useCallback(
    (cfg: OcrProviderConfig | null) => {
      setCustomOcrConfig(cfg);
      saveOcrProviderConfig(cfg).catch(() => {});
      setOcrSettingsVisible(false);
      if (cfg) {
        showToast("已保存自定义 OCR 服务配置");
      } else if (requiresCustomOcrConfig()) {
        showToast("已清除 OCR 服务配置");
      } else {
        showToast("已恢复默认 OCR 服务配置");
      }
      quota.refresh();
    },
    [quota, showToast],
  );

  // Selecting a built-in model clears any custom config so the built-in service
  // (free/premium) actually takes effect.
  const handleSelectModel = useCallback(
    (modelId: string) => {
      saveSelectedModelId(modelId).catch(() => {});
      // Clear BYOK so the built-in model is used.
      setCustomOcrConfig(null);
      saveOcrProviderConfig(null).catch(() => {});
      setOcrSettingsVisible(false);
      showToast(`已切换到 ${getBuiltinModel(modelId).label}`);
      quota.refresh();
    },
    [quota, showToast],
  );

  const handleRecharge = useCallback(
    async (pack: CreditPack) => {
      await quota.recharge(pack);
      showToast(`充值成功 +${pack.credits + pack.bonus} credits`);
    },
    [quota, showToast],
  );

  const handleClearTtsCache = useCallback(() => {
    setDialog({
      visible: true,
      title: "清空发音缓存",
      message: "确定要删除本地缓存的发音文件吗？\n下次听写会重新生成或下载。",
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

  const usingCustom = isCustomOcrConfigSet(customOcrConfig);
  const ocrDetail = usingCustom
    ? customOcrConfig!.model
    : requiresCustomOcrConfig()
      ? "未配置"
      : quota.model.label;

  const ttsDetail =
    ttsSource === "custom"
      ? isTtsProviderConfigSet(ttsConfig)
        ? ttsConfig.model
        : "未配置"
      : "有道词典";

  const appVersion = Constants.expoConfig?.version ?? "—";

  const sections: Section[] = [
    {
      key: "tts",
      title: "发音",
      rows: [
        {
          key: "tts-source",
          icon: "volume-medium-outline",
          label: "发音源",
          detail: ttsDetail,
          onPress: () => setTtsSettingsVisible(true),
        },
      ],
    },
    {
      key: "ocr",
      title: "识别服务",
      rows: [
        {
          key: "ocr-model",
          icon: "scan-outline",
          label: "识别模型",
          detail: ocrDetail,
          onPress: () => setOcrSettingsVisible(true),
        },
        {
          key: "ocr-credits",
          icon: "wallet-outline",
          label: "Credits 余额",
          detail: `${quota.credits}`,
        },
        {
          key: "ocr-recharge",
          icon: "card-outline",
          label: "充值",
          onPress: () => setRechargeVisible(true),
        },
      ],
    },
    {
      key: "data",
      title: "数据",
      rows: [
        {
          key: "clear-cache",
          icon: "trash-outline",
          label: "清空发音缓存",
          onPress: handleClearTtsCache,
          destructive: true,
        },
      ],
    },
    {
      key: "about",
      title: "关于",
      rows: [
        {
          key: "version",
          icon: "information-circle-outline",
          label: "版本",
          detail: appVersion,
        },
      ],
    },
  ];

  return (
    <SafeAreaView
      style={[styles.container, { backgroundColor: colors.background }]}
      edges={["top", "bottom", "left", "right"]}
    >
      <View style={styles.header}>
        <IconButton
          icon="arrow-back"
          onPress={() => navigation.goBack()}
          accessibilityLabel="返回"
        />

        <Text style={[styles.headerTitle, { color: colors.foreground }]}>
          设置
        </Text>

        <View style={[styles.headerBtn, styles.headerBtnPlaceholder]} />
      </View>

      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* 外观 — theme selector */}
        <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
          外观
        </Text>
        <View
          style={[
            styles.card,
            {
              backgroundColor: colors.surfaceRaised,
              borderColor: colors.borderSubtle,
            },
          ]}
        >
          <View style={styles.themeRow}>
            {[
              { key: "light" as const, label: "浅色", icon: "sunny" as const },
              { key: "dark" as const, label: "深色", icon: "moon" as const },
            ].map((opt) => {
              const active = mode === opt.key;
              return (
                <TouchableOpacity
                  key={opt.key}
                  style={[
                    styles.themeChip,
                    {
                      borderColor: active ? colors.primary : colors.border,
                      backgroundColor: active
                        ? colors.primarySoft
                        : colors.surface,
                    },
                  ]}
                  onPress={() => setMode(opt.key)}
                  activeOpacity={0.7}
                  accessibilityRole="radio"
                  accessibilityLabel={`${opt.label}主题`}
                  accessibilityState={{ selected: active }}
                >
                  <Ionicons
                    name={opt.icon}
                    size={16}
                    color={active ? colors.primary : colors.muted}
                  />
                  <Text
                    style={[
                      styles.themeChipText,
                      { color: active ? colors.primary : colors.foreground },
                    ]}
                  >
                    {opt.label}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>
        </View>

        {/* 声音 — sound effects toggle */}
        <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
          声音
        </Text>
        <View
          style={[
            styles.card,
            {
              backgroundColor: colors.surfaceRaised,
              borderColor: colors.borderSubtle,
            },
          ]}
        >
          <View style={styles.row}>
            <Ionicons
              name="musical-notes-outline"
              size={18}
              color={colors.secondary}
            />
            <Text style={[styles.rowLabel, { color: colors.foreground }]}>
              提示音
            </Text>
            <Switch
              value={soundOn}
              onValueChange={handleToggleSound}
              accessibilityLabel="提示音"
              accessibilityRole="switch"
              accessibilityState={{ checked: soundOn }}
              trackColor={{ false: colors.track, true: colors.primarySoft }}
              thumbColor={soundOn ? colors.primary : colors.background}
            />
          </View>
          <View
            style={[
              styles.row,
              {
                borderTopWidth: StyleSheet.hairlineWidth,
                borderTopColor: colors.borderSubtle,
              },
            ]}
          >
            <Ionicons
              name="language-outline"
              size={18}
              color={colors.secondary}
            />
            <Text style={[styles.rowLabel, { color: colors.foreground }]}>
              朗读中文释义
            </Text>
            <Switch
              value={readTranslationOn}
              onValueChange={handleToggleReadTranslation}
              accessibilityLabel="朗读中文释义"
              accessibilityRole="switch"
              accessibilityState={{ checked: readTranslationOn }}
              trackColor={{ false: colors.track, true: colors.primarySoft }}
              thumbColor={readTranslationOn ? colors.primary : colors.background}
            />
          </View>
          <View
            style={[
              styles.row,
              {
                borderTopWidth: StyleSheet.hairlineWidth,
                borderTopColor: colors.borderSubtle,
              },
            ]}
          >
            <Ionicons
              name="speedometer-outline"
              size={18}
              color={colors.secondary}
            />
            <Text style={[styles.rowLabel, { color: colors.foreground }]}>
              语速
            </Text>
            <Text
              style={[styles.rowDetail, { color: colors.muted }]}
              accessibilityLabel={`当前语速 ${speechRate.toFixed(1)}`}
            >
              {speechRate.toFixed(1)}x
            </Text>
          </View>
          <View style={styles.sliderRow}>
            <Slider
              min={MIN_SPEECH_RATE}
              max={MAX_SPEECH_RATE}
              step={0.1}
              value={speechRate}
              onValueChange={handleSpeechRateChange}
              accessibilityLabel="朗读语速"
            />
          </View>
        </View>

        {/* 听写 — default playback interval */}
        <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
          听写
        </Text>
        <View
          style={[
            styles.card,
            {
              backgroundColor: colors.surfaceRaised,
              borderColor: colors.borderSubtle,
            },
          ]}
        >
          <View style={styles.row}>
            <Ionicons
              name="timer-outline"
              size={18}
              color={colors.secondary}
            />
            <Text style={[styles.rowLabel, { color: colors.foreground }]}>
              默认间隔
            </Text>
            <Text
              style={[styles.rowDetail, { color: colors.muted }]}
              accessibilityLabel={`当前默认间隔 ${intervalSec.toFixed(1)} 秒`}
            >
              {intervalSec.toFixed(1)}s
            </Text>
          </View>
          <View style={styles.sliderRow}>
            <Slider
              min={MIN_INTERVAL_SEC}
              max={MAX_INTERVAL_SEC}
              step={INTERVAL_STEP}
              value={intervalSec}
              onValueChange={handleIntervalChange}
              accessibilityLabel="默认听写间隔秒数"
            />
          </View>
        </View>

        {/* Other sections */}
        {sections.map((section) => (
          <View key={section.key}>
            <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
              {section.title}
            </Text>
            <View
              style={[
                styles.card,
                {
                  backgroundColor: colors.surfaceRaised,
                  borderColor: colors.borderSubtle,
                },
              ]}
            >
              {section.rows.map((row, idx) => (
                <TouchableOpacity
                  key={row.key}
                  style={[
                    styles.row,
                    idx < section.rows.length - 1 && {
                      borderBottomWidth: StyleSheet.hairlineWidth,
                      borderBottomColor: colors.borderSubtle,
                    },
                  ]}
                  onPress={row.onPress}
                  disabled={!row.onPress}
                  activeOpacity={0.7}
                >
                  <Ionicons
                    name={row.icon}
                    size={18}
                    color={row.destructive ? colors.danger : colors.secondary}
                  />
                  <Text
                    style={[
                      styles.rowLabel,
                      {
                        color: row.destructive
                          ? colors.danger
                          : colors.foreground,
                      },
                    ]}
                  >
                    {row.label}
                  </Text>
                  {row.detail ? (
                    <Text
                      style={[styles.rowDetail, { color: colors.muted }]}
                      numberOfLines={1}
                    >
                      {row.detail}
                    </Text>
                  ) : null}
                  {row.onPress ? (
                    <Ionicons
                      name="chevron-forward"
                      size={16}
                      color={colors.subtle}
                    />
                  ) : null}
                </TouchableOpacity>
              ))}
            </View>
            {section.key === "ocr" ? (
              <View
                style={[
                  styles.disclaimer,
                  {
                    backgroundColor: colors.surface,
                    borderColor: colors.borderSubtle,
                  },
                ]}
              >
                <Ionicons
                  name="information-circle-outline"
                  size={13}
                  color={colors.subtle}
                />
                <Text
                  style={[styles.disclaimerText, { color: colors.subtle }]}
                >
                  {OCR_DISCLAIMER}
                </Text>
              </View>
            ) : null}
          </View>
        ))}
      </ScrollView>

      <OcrSettingsModal
        visible={ocrSettingsVisible}
        value={customOcrConfig}
        onClose={() => setOcrSettingsVisible(false)}
        onSave={handleSaveOcrConfig}
        onSelectModel={handleSelectModel}
        credits={quota.credits}
        onRecharge={() => {
          setOcrSettingsVisible(false);
          setRechargeVisible(true);
        }}
      />
      <RechargeModal
        visible={rechargeVisible}
        credits={quota.credits}
        onClose={() => setRechargeVisible(false)}
        onPurchase={handleRecharge}
      />
      <TtsSettingsModal
        visible={ttsSettingsVisible}
        source={ttsSource}
        config={ttsConfig}
        onClose={() => setTtsSettingsVisible(false)}
        onSelectSource={handleSelectTtsSource}
        onSaveConfig={handleSaveTtsConfig}
      />
      <ConfirmDialog
        visible={dialog?.visible}
        title={dialog?.title}
        message={dialog?.message}
        confirmLabel={dialog?.confirmLabel}
        destructive
        onConfirm={dialog?.action ?? (() => {})}
        onCancel={() => setDialog((d) => (d ? { ...d, visible: false } : null))}
      />
      <Toast toast={toast} onActionPress={hideToast} />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
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
    width: 36,
    height: 36,
  },
  headerBtnPlaceholder: {
    backgroundColor: "transparent",
  },
  headerTitle: {
    fontFamily: fonts.displayZh,
    fontSize: 18,
    letterSpacing: 0.3,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    width: "100%",
    maxWidth: 640,
    alignSelf: "center",
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing["2xl"],
    gap: spacing.xs,
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: "600",
    marginTop: spacing.lg,
    marginBottom: spacing.xs,
    paddingHorizontal: spacing.xs,
  },
  card: {
    borderRadius: radii.card,
    borderWidth: 1,
    overflow: "hidden",
  },
  themeRow: {
    flexDirection: "row",
    gap: spacing.sm,
    padding: spacing.md,
  },
  themeChip: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.xs,
    paddingVertical: spacing.md,
    borderRadius: radii.control,
    borderWidth: 1.5,
  },
  themeChipText: {
    fontSize: 14,
    fontWeight: "600",
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md + 2,
    minHeight: 48,
  },
  rowLabel: {
    flex: 1,
    fontSize: 15,
    fontWeight: "500",
  },
  rowDetail: {
    fontSize: 13,
    fontWeight: "500",
    maxWidth: 140,
  },
  disclaimer: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    marginTop: spacing.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radii.control,
    borderWidth: StyleSheet.hairlineWidth,
  },
  disclaimerText: {
    fontSize: 11,
    flexShrink: 1,
  },
  sliderRow: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
  },
});
