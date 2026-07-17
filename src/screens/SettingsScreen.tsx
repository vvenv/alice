import { Ionicons } from "@expo/vector-icons";
import { useNavigation } from "@react-navigation/native";
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
import { Toast } from "../components/Toast";
import { useToast } from "../hooks/useToast";
import { loadSoundEnabled, setSoundEnabled } from "../lib/sound";
import { fonts, radii, spacing } from "../lib/designTokens";
import {
  isCustomOcrConfigSet,
  loadOcrProviderConfig,
  requiresCustomOcrConfig,
  saveOcrProviderConfig,
  type OcrProviderConfig,
} from "../lib/ocrConfig";
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

  useEffect(() => {
    loadSoundEnabled().then(setSoundOn);
  }, []);

  const handleToggleSound = useCallback((value: boolean) => {
    setSoundOn(value);
    setSoundEnabled(value);
  }, []);

  const [customOcrConfig, setCustomOcrConfig] =
    useState<OcrProviderConfig | null>(null);
  const [ocrSettingsVisible, setOcrSettingsVisible] = useState(false);
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
    },
    [showToast],
  );

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

  const usingCustom = isCustomOcrConfigSet(customOcrConfig);
  const ocrDetail = usingCustom
    ? customOcrConfig!.model
    : requiresCustomOcrConfig()
      ? "未配置"
      : "内置服务";

  const appVersion = Constants.expoConfig?.version ?? "—";

  const sections: Section[] = [
    {
      key: "ocr",
      title: "OCR 服务",
      rows: [
        {
          key: "ocr-config",
          icon: "server-outline",
          label: "服务配置",
          detail: ocrDetail,
          onPress: () => setOcrSettingsVisible(true),
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
          </View>
        ))}
      </ScrollView>

      <OcrSettingsModal
        visible={ocrSettingsVisible}
        value={customOcrConfig}
        onClose={() => setOcrSettingsVisible(false)}
        onSave={handleSaveOcrConfig}
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
});
