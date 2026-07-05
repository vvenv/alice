import { useEffect, useState } from "react";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { ActivityIndicator, StyleSheet, View } from "react-native";
import { StatusBar } from "expo-status-bar";

import type { RootStackParamList } from "./src/navigation/types";
import { AuthScreen } from "./src/screens/AuthScreen";
import { DictationScreen } from "./src/screens/DictationScreen";
import { HomeScreen } from "./src/screens/HomeScreen";
import { loadPersistedCode } from "./src/lib/auth";
import { ThemeProvider, useThemeColors } from "./src/lib/theme";

export type { RootStackParamList };

const Stack = createNativeStackNavigator<RootStackParamList>();

function AppContent() {
  const colors = useThemeColors();
  const [ready, setReady] = useState(false);
  const [authed, setAuthed] = useState(false);

  useEffect(() => {
    (async () => {
      const code = await loadPersistedCode();
      setAuthed(code !== null);
      setReady(true);
    })();
  }, []);

  if (!ready) {
    return (
      <View style={[styles.loadingContainer, { backgroundColor: colors.surface }]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <>
      <StatusBar style={colors.foreground === "#ffffff" ? "light" : "dark"} />
      <NavigationContainer>
        <Stack.Navigator
          screenOptions={{
            headerShown: false,
            animation: "slide_from_right",
          }}
        >
          {!authed ? (
            <Stack.Screen name="Auth">
              {() => (
                <AuthScreen onAuthenticated={() => setAuthed(true)} />
              )}
            </Stack.Screen>
          ) : (
            <>
              <Stack.Screen
                name="Home"
                options={{ headerShown: false, gestureEnabled: false }}
              >
                {() => <HomeScreen />}
              </Stack.Screen>
              <Stack.Screen
                name="Dictation"
                options={{ headerShown: false, gestureEnabled: false }}
              >
                {(props) => (
                  <DictationScreen
                    words={props.route.params.words}
                    intervalSec={props.route.params.intervalSec}
                    autoNext={props.route.params.autoNext}
                    onEnd={() => props.navigation.goBack()}
                  />
                )}
              </Stack.Screen>
            </>
          )}
        </Stack.Navigator>
      </NavigationContainer>
    </>
  );
}

export default function App() {
  return (
    <ThemeProvider>
      <AppContent />
    </ThemeProvider>
  );
}

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
});
