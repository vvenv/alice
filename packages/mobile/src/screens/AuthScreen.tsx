import { useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import { authenticate } from "../lib/auth";

interface AuthScreenProps {
  onAuthenticated: () => void;
}

export function AuthScreen({ onAuthenticated }: AuthScreenProps) {
  const [code, setCode] = useState("");
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState(false);

  const handleSubmit = async () => {
    if (code.length !== 4 || busy) return;
    setBusy(true);
    setError(false);
    try {
      const ok = await authenticate(code);
      if (ok) {
        onAuthenticated();
        return;
      }
      setError(true);
      setCode("");
    } finally {
      setBusy(false);
    }
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === "ios" ? "padding" : "height"}
    >
      <View style={styles.inner}>
        <View style={styles.header}>
          <Text style={styles.title}>听写练习</Text>
          <Text style={styles.subtitle}>请输入使用码</Text>
        </View>

        <View style={styles.form}>
          <TextInput
            style={[styles.input, error && styles.inputError]}
            keyboardType="number-pad"
            maxLength={4}
            value={code}
            onChangeText={(text) => {
              const next = text.replace(/[^0-9]/g, "").slice(0, 4);
              setCode(next);
              setError(false);
            }}
            placeholder="••••"
            placeholderTextColor="#ccc"
            secureTextEntry
            textAlign="center"
            editable={!busy}
            autoFocus
          />
          {error ? (
            <Text style={styles.errorText}>使用码不正确</Text>
          ) : null}

          <TouchableOpacity
            style={[
              styles.button,
              (code.length !== 4 || busy) && styles.buttonDisabled,
            ]}
            onPress={handleSubmit}
            disabled={code.length !== 4 || busy}
            activeOpacity={0.7}
          >
            {busy ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={styles.buttonText}>进入</Text>
            )}
          </TouchableOpacity>
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#f8f9fa",
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
    color: "#1a1a2e",
  },
  subtitle: {
    marginTop: 8,
    fontSize: 14,
    color: "#888",
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
    borderColor: "#e2e2e2",
    borderRadius: 12,
    paddingHorizontal: 16,
    fontSize: 28,
    fontWeight: "600",
    color: "#1a1a2e",
    letterSpacing: 12,
    backgroundColor: "#fff",
  },
  inputError: {
    borderColor: "#e74c3c",
  },
  errorText: {
    color: "#e74c3c",
    fontSize: 13,
  },
  button: {
    width: "100%",
    height: 50,
    backgroundColor: "#4a6cf7",
    borderRadius: 12,
    justifyContent: "center",
    alignItems: "center",
  },
  buttonDisabled: {
    opacity: 0.4,
  },
  buttonText: {
    color: "#fff",
    fontSize: 17,
    fontWeight: "600",
  },
});
