import { Ionicons } from "@expo/vector-icons";
import { useCallback, useEffect, useState } from "react";
import {
  ActivityIndicator,
  Keyboard,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import { testTtsConfig } from "../lib/tts";
import {
  TTS_PROVIDER_PRESETS,
  isTtsProviderConfigSet,
  type TtsApiKind,
  type TtsProviderConfig,
  type TtsSource,
} from "../lib/ttsConfig";
import { fonts, radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

type TestState =
  | { kind: "idle" }
  | { kind: "testing" }
  | { kind: "ok" }
  | { kind: "error"; message: string };

interface TtsSettingsModalProps {
  visible: boolean;
  /** Currently active source. */
  source: TtsSource;
  /** Saved provider config (null = none). */
  config: TtsProviderConfig | null;
  onClose: () => void;
  /** Activate a source immediately (Youdao chip). */
  onSelectSource: (source: TtsSource) => void;
  /** Persist the provider config; null clears it and reverts to Youdao. */
  onSaveConfig: (cfg: TtsProviderConfig | null) => void;
}

const CUSTOM_PRESET_ID = "custom";

export function TtsSettingsModal({
  visible,
  source,
  config,
  onClose,
  onSelectSource,
  onSaveConfig,
}: TtsSettingsModalProps) {
  const colors = useThemeColors();

  const [view, setView] = useState<TtsSource>("youdao");
  const [presetId, setPresetId] = useState("mimo");
  const [api, setApi] = useState<TtsApiKind>("chat");
  const [baseUrl, setBaseUrl] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [model, setModel] = useState("");
  const [voiceEn, setVoiceEn] = useState("");
  const [voiceZh, setVoiceZh] = useState("");
  const [responseFormat, setResponseFormat] = useState<string | undefined>(
    undefined,
  );
  const [showKey, setShowKey] = useState(false);
  const [test, setTest] = useState<TestState>({ kind: "idle" });

  const applyPreset = useCallback((id: string) => {
    const preset = TTS_PROVIDER_PRESETS.find((p) => p.id === id);
    if (!preset) return;
    setPresetId(preset.id);
    setApi(preset.api);
    setBaseUrl(preset.baseUrl);
    setModel(preset.model);
    setVoiceEn(preset.voiceEn);
    setVoiceZh(preset.voiceZh);
    setResponseFormat(preset.responseFormat);
    setTest({ kind: "idle" });
  }, []);

  // Sync local form + active view whenever the modal opens.
  useEffect(() => {
    if (!visible) return;
    setView(source);
    setShowKey(false);
    setTest({ kind: "idle" });
    if (isTtsProviderConfigSet(config)) {
      setPresetId(
        TTS_PROVIDER_PRESETS.find(
          (p) => p.baseUrl === config.baseUrl && p.model === config.model,
        )?.id ?? CUSTOM_PRESET_ID,
      );
      setApi(config.api);
      setBaseUrl(config.baseUrl);
      setApiKey(config.apiKey);
      setModel(config.model);
      setVoiceEn(config.voiceEn);
      setVoiceZh(config.voiceZh);
      setResponseFormat(config.responseFormat);
    } else {
      applyPreset("mimo");
      setApiKey("");
    }
  }, [visible, source, config, applyPreset]);

  const canSave =
    baseUrl.trim().length > 0 &&
    apiKey.trim().length > 0 &&
    model.trim().length > 0;

  const handleSave = useCallback(() => {
    if (!canSave) return;
    Keyboard.dismiss();
    const preset = TTS_PROVIDER_PRESETS.find((p) => p.id === presetId);
    onSaveConfig({
      api,
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      model: model.trim(),
      voiceEn: voiceEn.trim(),
      voiceZh: voiceZh.trim(),
      responseFormat: presetId === CUSTOM_PRESET_ID ? undefined : preset?.responseFormat,
    });
  }, [
    api,
    apiKey,
    baseUrl,
    canSave,
    model,
    onSaveConfig,
    presetId,
    voiceEn,
    voiceZh,
  ]);

  const handleClear = useCallback(() => {
    Keyboard.dismiss();
    onSaveConfig(null);
  }, [onSaveConfig]);

  const handleTest = useCallback(async () => {
    if (!canSave || test.kind === "testing") return;
    setTest({ kind: "testing" });
    try {
      await testTtsConfig({
        api,
        baseUrl: baseUrl.trim(),
        apiKey: apiKey.trim(),
        model: model.trim(),
        voiceEn: voiceEn.trim(),
        voiceZh: voiceZh.trim(),
        responseFormat,
      });
      setTest({ kind: "ok" });
    } catch (e) {
      setTest({
        kind: "error",
        message: e instanceof Error ? e.message : "测试失败",
      });
    }
  }, [api, apiKey, baseUrl, canSave, model, responseFormat, test.kind, voiceEn, voiceZh]);

  const statusLine =
    view === "youdao"
      ? "当前使用有道词典发音"
      : source === "custom" && isTtsProviderConfigSet(config)
        ? "当前使用自定义发音服务"
        : "保存后启用自定义发音";

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <Pressable
        style={[styles.backdrop, { backgroundColor: colors.overlay }]}
        onPress={onClose}
      >
        <Pressable
          style={[
            styles.sheet,
            {
              backgroundColor: colors.background,
              borderColor: colors.border,
            },
          ]}
          onPress={() => {}}
        >
          <View style={styles.header}>
            <Text style={[styles.title, { color: colors.foreground }]}>
              发音源
            </Text>
            <TouchableOpacity
              onPress={onClose}
              hitSlop={8}
              activeOpacity={0.6}
              accessibilityLabel="关闭"
            >
              <Ionicons name="close" size={22} color={colors.muted} />
            </TouchableOpacity>
          </View>

          <ScrollView
            style={styles.body}
            contentContainerStyle={styles.bodyContent}
            keyboardShouldPersistTaps="handled"
          >
            <Text style={[styles.statusLine, { color: colors.muted }]}>
              {statusLine}
            </Text>

            <View style={styles.tierRow}>
              <TouchableOpacity
                style={[
                  styles.tierChip,
                  {
                    borderColor: view === "youdao" ? colors.primary : colors.border,
                    backgroundColor:
                      view === "youdao" ? colors.primarySoft : colors.surface,
                  },
                ]}
                onPress={() => {
                  setView("youdao");
                  onSelectSource("youdao");
                }}
                activeOpacity={0.7}
                accessibilityRole="radio"
                accessibilityLabel="有道词典发音"
                accessibilityState={{ selected: view === "youdao" }}
              >
                <Text
                  style={[
                    styles.tierChipText,
                    {
                      color:
                        view === "youdao" ? colors.primary : colors.foreground,
                    },
                  ]}
                >
                  有道词典
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[
                  styles.tierChip,
                  {
                    borderColor: view === "custom" ? colors.primary : colors.border,
                    backgroundColor:
                      view === "custom" ? colors.primarySoft : colors.surface,
                  },
                ]}
                onPress={() => setView("custom")}
                activeOpacity={0.7}
                accessibilityRole="radio"
                accessibilityLabel="自定义接口发音"
                accessibilityState={{ selected: view === "custom" }}
              >
                <Text
                  style={[
                    styles.tierChipText,
                    {
                      color:
                        view === "custom" ? colors.primary : colors.foreground,
                    },
                  ]}
                >
                  自定义接口
                </Text>
              </TouchableOpacity>
            </View>

            {view === "youdao" ? (
              <View
                style={[
                  styles.infoCard,
                  {
                    backgroundColor: colors.surfaceRaised,
                    borderColor: colors.borderSubtle,
                  },
                ]}
              >
                <Text style={[styles.infoDesc, { color: colors.muted }]}>
                  使用有道词典免费单词发音，首次播放后本地缓存；中文释义与未缓存的词由系统
                  TTS 朗读。
                </Text>
                <Text style={[styles.infoDesc, { color: colors.muted }]}>
                  自定义接口可使用 OpenAI 兼容的大模型 TTS（如小米 MiMo，
                  限时免费），发音更自然；接口失败或离线时自动回落系统 TTS。
                </Text>
              </View>
            ) : null}

            {view === "custom" ? (
              <>
                <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
                  服务商预设
                </Text>
                <View style={styles.presetRow}>
                  {TTS_PROVIDER_PRESETS.map((preset) => {
                    const active = preset.id === presetId;
                    return (
                      <TouchableOpacity
                        key={preset.id}
                        style={[
                          styles.presetChip,
                          {
                            borderColor: active ? colors.primary : colors.border,
                            backgroundColor: active
                              ? colors.primarySoft
                              : colors.surface,
                          },
                        ]}
                        onPress={() => applyPreset(preset.id)}
                        activeOpacity={0.7}
                      >
                        <Text
                          style={[
                            styles.presetChipText,
                            {
                              color: active
                                ? colors.primary
                                : colors.foreground,
                            },
                          ]}
                        >
                          {preset.label}
                        </Text>
                      </TouchableOpacity>
                    );
                  })}
                </View>
                {(() => {
                  const preset = TTS_PROVIDER_PRESETS.find(
                    (p) => p.id === presetId,
                  );
                  return preset?.hint ? (
                    <Text style={[styles.hint, { color: colors.subtle }]}>
                      {preset.hint}
                    </Text>
                  ) : null;
                })()}

                {presetId === CUSTOM_PRESET_ID ? (
                  <>
                    <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
                      接口类型
                    </Text>
                    <View style={styles.tierRow}>
                      <TouchableOpacity
                        style={[
                          styles.tierChip,
                          {
                            borderColor:
                              api === "speech" ? colors.primary : colors.border,
                            backgroundColor:
                              api === "speech"
                                ? colors.primarySoft
                                : colors.surface,
                          },
                        ]}
                        onPress={() => setApi("speech")}
                        activeOpacity={0.7}
                      >
                        <Text
                          style={[
                            styles.tierChipText,
                            {
                              color:
                                api === "speech"
                                  ? colors.primary
                                  : colors.foreground,
                            },
                          ]}
                        >
                          /audio/speech
                        </Text>
                      </TouchableOpacity>
                      <TouchableOpacity
                        style={[
                          styles.tierChip,
                          {
                            borderColor:
                              api === "chat" ? colors.primary : colors.border,
                            backgroundColor:
                              api === "chat"
                                ? colors.primarySoft
                                : colors.surface,
                          },
                        ]}
                        onPress={() => setApi("chat")}
                        activeOpacity={0.7}
                      >
                        <Text
                          style={[
                            styles.tierChipText,
                            {
                              color:
                                api === "chat"
                                  ? colors.primary
                                  : colors.foreground,
                            },
                          ]}
                        >
                          Chat Completions
                        </Text>
                      </TouchableOpacity>
                    </View>
                    <Text style={[styles.hint, { color: colors.subtle }]}>
                      标准 OpenAI TTS 选 /audio/speech；小米 MiMo 等
                      经对话接口合成选 Chat Completions。
                    </Text>
                  </>
                ) : null}

                <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
                  接口地址 (Base URL)
                </Text>
                <TextInput
                  style={[
                    styles.input,
                    {
                      borderColor: colors.border,
                      backgroundColor: colors.surfaceSunken,
                      color: colors.foreground,
                    },
                  ]}
                  value={baseUrl}
                  onChangeText={(t) => {
                    setBaseUrl(t);
                    setTest({ kind: "idle" });
                  }}
                  placeholder="https://api.example.com/v1"
                  placeholderTextColor={colors.subtle}
                  autoCapitalize="none"
                  autoCorrect={false}
                  keyboardType="url"
                />

                <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
                  API Key
                </Text>
                <View
                  style={[
                    styles.input,
                    styles.keyRow,
                    {
                      borderColor: colors.border,
                      backgroundColor: colors.surfaceSunken,
                    },
                  ]}
                >
                  <TextInput
                    style={[styles.keyInput, { color: colors.foreground }]}
                    value={apiKey}
                    onChangeText={(t) => {
                      setApiKey(t);
                      setTest({ kind: "idle" });
                    }}
                    placeholder="sk-..."
                    placeholderTextColor={colors.subtle}
                    autoCapitalize="none"
                    autoCorrect={false}
                    secureTextEntry={!showKey}
                  />
                  <TouchableOpacity
                    onPress={() => setShowKey((v) => !v)}
                    hitSlop={8}
                    activeOpacity={0.6}
                    accessibilityLabel={showKey ? "隐藏密钥" : "显示密钥"}
                  >
                    <Ionicons
                      name={showKey ? "eye-off-outline" : "eye-outline"}
                      size={20}
                      color={colors.subtle}
                    />
                  </TouchableOpacity>
                </View>

                <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
                  模型名称
                </Text>
                <TextInput
                  style={[
                    styles.input,
                    {
                      borderColor: colors.border,
                      backgroundColor: colors.surfaceSunken,
                      color: colors.foreground,
                    },
                  ]}
                  value={model}
                  onChangeText={(t) => {
                    setModel(t);
                    setTest({ kind: "idle" });
                  }}
                  placeholder="例如 mimo-v2.5-tts"
                  placeholderTextColor={colors.subtle}
                  autoCapitalize="none"
                  autoCorrect={false}
                />

                <View style={styles.voiceRow}>
                  <View style={styles.voiceField}>
                    <Text
                      style={[styles.sectionLabel, { color: colors.subtle }]}
                    >
                      英文音色
                    </Text>
                    <TextInput
                      style={[
                        styles.input,
                        {
                          borderColor: colors.border,
                          backgroundColor: colors.surfaceSunken,
                          color: colors.foreground,
                        },
                      ]}
                      value={voiceEn}
                      onChangeText={(t) => {
                        setVoiceEn(t);
                        setTest({ kind: "idle" });
                      }}
                      placeholder="默认"
                      placeholderTextColor={colors.subtle}
                      autoCapitalize="none"
                      autoCorrect={false}
                    />
                  </View>
                  <View style={styles.voiceField}>
                    <Text
                      style={[styles.sectionLabel, { color: colors.subtle }]}
                    >
                      中文音色
                    </Text>
                    <TextInput
                      style={[
                        styles.input,
                        {
                          borderColor: colors.border,
                          backgroundColor: colors.surfaceSunken,
                          color: colors.foreground,
                        },
                      ]}
                      value={voiceZh}
                      onChangeText={(t) => {
                        setVoiceZh(t);
                        setTest({ kind: "idle" });
                      }}
                      placeholder="默认"
                      placeholderTextColor={colors.subtle}
                      autoCapitalize="none"
                      autoCorrect={false}
                    />
                  </View>
                </View>
                <Text style={[styles.hint, { color: colors.subtle }]}>
                  留空使用服务商默认音色；修改音色或语速后会重新生成发音。
                </Text>

                {test.kind === "ok" ? (
                  <View
                    style={[
                      styles.testResult,
                      { backgroundColor: colors.primarySoft },
                    ]}
                  >
                    <Ionicons
                      name="checkmark-circle"
                      size={16}
                      color={colors.primary}
                    />
                    <Text style={[styles.testText, { color: colors.primary }]}>
                      连接成功，已播放试听
                    </Text>
                  </View>
                ) : null}
                {test.kind === "error" ? (
                  <View
                    style={[
                      styles.testResult,
                      { backgroundColor: colors.dangerSoft },
                    ]}
                  >
                    <Ionicons
                      name="alert-circle"
                      size={16}
                      color={colors.danger}
                    />
                    <Text style={[styles.testText, { color: colors.danger }]}>
                      {test.message}
                    </Text>
                  </View>
                ) : null}

                <View style={styles.testRow}>
                  <TouchableOpacity
                    style={[
                      styles.testBtn,
                      {
                        borderColor: colors.border,
                        backgroundColor: colors.surface,
                      },
                      !canSave && styles.btnDisabled,
                    ]}
                    onPress={handleTest}
                    disabled={!canSave || test.kind === "testing"}
                    activeOpacity={0.7}
                  >
                    {test.kind === "testing" ? (
                      <ActivityIndicator
                        size="small"
                        color={colors.foreground}
                      />
                    ) : (
                      <Text
                        style={[styles.testBtnText, { color: colors.foreground }]}
                      >
                        测试并试听
                      </Text>
                    )}
                  </TouchableOpacity>
                </View>
              </>
            ) : null}
          </ScrollView>

          <View style={[styles.footer, { borderColor: colors.border }]}>
            {view === "custom" ? (
              <>
                {isTtsProviderConfigSet(config) ? (
                  <TouchableOpacity
                    style={[
                      styles.footerBtn,
                      styles.footerBtnOutline,
                      { borderColor: colors.border },
                    ]}
                    onPress={handleClear}
                    activeOpacity={0.7}
                  >
                    <Text
                      style={[styles.footerBtnText, { color: colors.muted }]}
                    >
                      清除配置
                    </Text>
                  </TouchableOpacity>
                ) : null}
                <TouchableOpacity
                  style={[
                    styles.footerBtn,
                    { backgroundColor: colors.primary },
                    !canSave && styles.btnDisabled,
                  ]}
                  onPress={handleSave}
                  disabled={!canSave}
                  activeOpacity={0.7}
                >
                  <Text
                    style={[styles.footerBtnText, { color: colors.background }]}
                  >
                    保存
                  </Text>
                </TouchableOpacity>
              </>
            ) : (
              <TouchableOpacity
                style={[
                  styles.footerBtn,
                  { backgroundColor: colors.primary },
                ]}
                onPress={onClose}
                activeOpacity={0.7}
              >
                <Text
                  style={[styles.footerBtnText, { color: colors.background }]}
                >
                  完成
                </Text>
              </TouchableOpacity>
            )}
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    padding: spacing.lg,
  },
  sheet: {
    width: "100%",
    maxWidth: 380,
    maxHeight: "88%",
    borderRadius: radii.card,
    borderWidth: 1,
    overflow: "hidden",
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  title: {
    fontFamily: fonts.displayZh,
    fontSize: 17,
  },
  body: {
    paddingHorizontal: spacing.lg,
  },
  bodyContent: {
    paddingVertical: spacing.md,
    gap: spacing.xs,
  },
  statusLine: {
    fontSize: 12,
    marginBottom: spacing.xs,
  },
  tierRow: {
    flexDirection: "row",
    gap: spacing.xs,
    marginVertical: spacing.xs,
  },
  tierChip: {
    flex: 1,
    paddingVertical: spacing.sm + 2,
    borderRadius: radii.control,
    borderWidth: 1.5,
    alignItems: "center",
  },
  tierChipText: {
    fontSize: 13,
    fontWeight: "600",
  },
  infoCard: {
    borderRadius: radii.surface,
    borderWidth: 1,
    padding: spacing.md,
    gap: spacing.xs,
    marginTop: spacing.xs,
  },
  infoDesc: {
    fontSize: 13,
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: "600",
    marginTop: spacing.sm,
    marginBottom: spacing.xs,
  },
  presetRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: spacing.xs,
  },
  presetChip: {
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: 6,
    borderRadius: radii.control,
    borderWidth: 1,
  },
  presetChipText: {
    fontSize: 12,
    fontWeight: "600",
  },
  input: {
    borderWidth: 1,
    borderRadius: radii.control,
    paddingHorizontal: spacing.md,
    paddingVertical: 10,
    fontSize: 14,
  },
  keyRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingVertical: 0,
    paddingRight: spacing.md,
  },
  keyInput: {
    flex: 1,
    fontSize: 14,
    paddingVertical: 10,
  },
  voiceRow: {
    flexDirection: "row",
    gap: spacing.sm,
  },
  voiceField: {
    flex: 1,
  },
  hint: {
    fontSize: 11,
    marginTop: 4,
    marginBottom: spacing.xs,
  },
  testResult: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: spacing.md,
    paddingVertical: 8,
    borderRadius: radii.control,
    marginTop: spacing.sm,
  },
  testText: {
    fontSize: 12,
    flexShrink: 1,
  },
  testRow: {
    marginTop: spacing.sm,
  },
  testBtn: {
    minHeight: 38,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radii.control,
    borderWidth: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  testBtnText: {
    fontSize: 14,
    fontWeight: "600",
  },
  footer: {
    flexDirection: "row",
    gap: spacing.sm,
    padding: spacing.lg,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  footerBtn: {
    flex: 1,
    minHeight: 44,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.sm,
    borderRadius: radii.button,
    justifyContent: "center",
    alignItems: "center",
  },
  footerBtnOutline: {
    borderWidth: 1.5,
  },
  footerBtnText: {
    fontSize: 15,
    fontWeight: "600",
  },
  btnDisabled: {
    opacity: 0.4,
  },
});
