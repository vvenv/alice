import { useState } from "react";
import {
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import { authenticate } from "../lib/auth";
import { useThemeColors } from "../lib/theme";

interface AuthScreenProps {
  onAuthenticated: () => void;
}

export function AuthScreen({ onAuthenticated }: AuthScreenProps) {
  const colors = useThemeColors();
  const [code, setCode] = useState("");
  const [error, setError] = useState(false);

  const handleSubmit = () => {
    if (code.length !== 4) return;
    setError(false);
    const ok = authenticate(code);
    if (ok) {
      onAuthenticated();
    } else {
      setError(true);
      setCode("");
    }
  };

  return (
    <KeyboardAvoidingView
      style={[styles.container, { backgroundColor: colors.background }]}
      behavior={Platform.OS === "ios" ? "padding" : "height"}
    >
      <View style={styles.inner}>
        <View style={styles.header}>
          <Text style={[styles.title, { color: colors.foreground }]}>听写练习</Text>
          <Text style={[styles.subtitle, { color: colors.muted }]}>请输入使用码</Text>
        </View>

        <View style={styles.form}>
          <TextInput
            style={[
              styles.input,
              { borderColor: error ? colors.danger : colors.border, color: colors.foreground, backgroundColor: colors.surfaceSunken },
            ]}
            keyboardType="number-pad"
            maxLength={4}
            value={code}
            onChangeText={(text) => {
              const next = text.replace(/[^0-9]/g, "").slice(0, 4);
              setCode(next);
              setError(false);
            }}
            placeholder="••••"
            placeholderTextColor={colors.subtle}
            textAlign="center"
            autoFocus
          />
          {error ? (
            <Text style={[styles.errorText, { color: colors.danger }]}>使用码不正确</Text>
          ) : null}

          <TouchableOpacity
            style={[
              styles.button,
              { backgroundColor: colors.primary },
              code.length !== 4 && styles.buttonDisabled,
            ]}
            onPress={handleSubmit}
            disabled={code.length !== 4}
            activeOpacity={0.7}
          >
            <Text style={[styles.buttonText, { color: colors.background }]}>进入</Text>
          </TouchableOpacity>
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  inner: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 32,
    gap: 32,
  },
  header: {
    alignItems: "center",
  },
  title: {
    fontSize: 24,
    fontWeight: "700",
  },
  subtitle: {
    marginTop: 8,
    fontSize: 14,
  },
  form: {
    width: "100%",
    maxWidth: 260,
    alignItems: "center",
    gap: 16,
  },
  input: {
    width: "100%",
    height: 56,
    borderWidth: 2,
    borderRadius: 12,
    paddingHorizontal: 16,
    fontSize: 28,
    fontWeight: "600",
    letterSpacing: 12,
    textAlign: "center",
  },
  errorText: {
    fontSize: 13,
  },
  button: {
    width: "100%",
    height: 50,
    borderRadius: 12,
    justifyContent: "center",
    alignItems: "center",
  },
  buttonDisabled: {
    opacity: 0.4,
  },
  buttonText: {
    fontSize: 17,
    fontWeight: "600",
  },
});
