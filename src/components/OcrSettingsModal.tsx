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

import { testOcrConfig } from "../lib/ocr";
import {
  isCustomOcrConfigSet,
  OCR_PROVIDER_PRESETS,
  requiresCustomOcrConfig,
  type OcrProviderConfig,
} from "../lib/ocrConfig";
import { fonts, radii, spacing } from "../lib/designTokens";
import { useThemeColors } from "../lib/theme";

interface OcrSettingsModalProps {
  visible: boolean;
  /** Current saved custom config (null = using built-in default on native). */
  value: OcrProviderConfig | null;
  onClose: () => void;
  /** Persist the config (null clears it). */
  onSave: (cfg: OcrProviderConfig | null) => void;
}

type TestState =
  | { kind: "idle" }
  | { kind: "testing" }
  | { kind: "ok" }
  | { kind: "error"; message: string };

export function OcrSettingsModal({
  visible,
  value,
  onClose,
  onSave,
}: OcrSettingsModalProps) {
  const colors = useThemeColors();

  const [baseUrl, setBaseUrl] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [model, setModel] = useState("");
  const [showKey, setShowKey] = useState(false);
  const [test, setTest] = useState<TestState>({ kind: "idle" });

  // Sync local form whenever the modal opens (so edits reset on reopen).
  useEffect(() => {
    if (visible) {
      setBaseUrl(value?.baseUrl ?? "");
      setApiKey(value?.apiKey ?? "");
      setModel(value?.model ?? "");
      setShowKey(false);
      setTest({ kind: "idle" });
    }
  }, [visible, value]);

  const applyPreset = useCallback((presetId: string) => {
    const preset = OCR_PROVIDER_PRESETS.find((p) => p.id === presetId);
    if (!preset) return;
    setBaseUrl(preset.baseUrl);
    setModel(preset.model);
    setTest({ kind: "idle" });
  }, []);

  const canSave =
    baseUrl.trim().length > 0 &&
    model.trim().length > 0 &&
    apiKey.trim().length > 0;

  const handleSave = useCallback(() => {
    if (!canSave) return;
    Keyboard.dismiss();
    onSave({
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      model: model.trim(),
    });
  }, [baseUrl, apiKey, model, canSave, onSave]);

  const handleClear = useCallback(() => {
    Keyboard.dismiss();
    onSave(null);
  }, [onSave]);

  const handleTest = useCallback(async () => {
    if (!canSave) return;
    setTest({ kind: "testing" });
    try {
      await testOcrConfig({
        baseUrl: baseUrl.trim(),
        apiKey: apiKey.trim(),
        model: model.trim(),
      });
      setTest({ kind: "ok" });
    } catch (e) {
      setTest({
        kind: "error",
        message: e instanceof Error ? e.message : "测试失败",
      });
    }
  }, [baseUrl, apiKey, model, canSave]);

  const usingCustom = isCustomOcrConfigSet(value);
  const webRequiresKey = requiresCustomOcrConfig();

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
              OCR 服务设置
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
              {usingCustom
                ? "当前使用自定义服务配置"
                : webRequiresKey
                  ? "尚未配置 — Web 版需自备 API Key"
                  : "当前使用内置服务配置"}
            </Text>
            {webRequiresKey && !usingCustom ? (
              <Text style={[styles.hint, { color: colors.subtle }]}>
                听写与词库不需要 Key；仅拍照识别需要。请选择下方服务商并填写密钥。
              </Text>
            ) : null}

            <Text style={[styles.sectionLabel, { color: colors.subtle }]}>
              服务商预设
            </Text>
            <View style={styles.presetRow}>
              {OCR_PROVIDER_PRESETS.map((preset) => {
                const active =
                  preset.baseUrl.length > 0 &&
                  preset.baseUrl === baseUrl.trim() &&
                  preset.model === model.trim();
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
                        { color: active ? colors.primary : colors.foreground },
                      ]}
                    >
                      {preset.label}
                    </Text>
                  </TouchableOpacity>
                );
              })}
            </View>

            <FieldLabel label="接口地址 (Base URL)" colors={colors} />
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
            <Text style={[styles.hint, { color: colors.subtle }]}>
              将自动拼接 /chat/completions，也可直接粘贴完整地址
            </Text>

            <FieldLabel label="API Key" colors={colors} />
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

            <FieldLabel label="模型名称" colors={colors} />
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
              placeholder="例如 gpt-4o-mini"
              placeholderTextColor={colors.subtle}
              autoCapitalize="none"
              autoCorrect={false}
            />
            <Text style={[styles.hint, { color: colors.subtle }]}>
              请填写支持图像识别的视觉模型
            </Text>

            {/* Test result */}
            {test.kind === "ok" ? (
              <View
                style={[
                  styles.testResult,
                  { backgroundColor: colors.dangerSoft },
                ]}
              >
                <Ionicons
                  name="checkmark-circle"
                  size={16}
                  color={colors.primary}
                />
                <Text style={[styles.testText, { color: colors.primary }]}>
                  连接成功，配置可用
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
                <Ionicons name="alert-circle" size={16} color={colors.danger} />
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
                  <ActivityIndicator size="small" color={colors.foreground} />
                ) : (
                  <Text
                    style={[styles.testBtnText, { color: colors.foreground }]}
                  >
                    测试连接
                  </Text>
                )}
              </TouchableOpacity>
            </View>
          </ScrollView>

          <View style={[styles.footer, { borderColor: colors.border }]}>
            <TouchableOpacity
              style={[
                styles.footerBtn,
                styles.footerBtnOutline,
                { borderColor: colors.border },
              ]}
              onPress={handleClear}
              activeOpacity={0.7}
            >
              <Text style={[styles.footerBtnText, { color: colors.muted }]}>
                {webRequiresKey ? "清除配置" : "恢复默认"}
              </Text>
            </TouchableOpacity>
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
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

function FieldLabel({
  label,
  colors,
}: {
  label: string;
  colors: ReturnType<typeof useThemeColors>;
}) {
  return (
    <Text style={[styles.sectionLabel, { color: colors.subtle }]}>{label}</Text>
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
    fontWeight: "700",
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
  // keyRow wraps the input + eye icon. It reuses `input` for the border/bg, so
  // the vertical padding is zeroed here — the inner TextInput controls height,
  // keeping this row aligned with the other inputs.
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
