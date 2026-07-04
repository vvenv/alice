import { useEffect, useState } from "react";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { ActivityIndicator, StyleSheet, View } from "react-native";
import { StatusBar } from "expo-status-bar";

import { AuthScreen } from "./src/screens/AuthScreen";
import { HomeScreen } from "./src/screens/HomeScreen";
import { loadPersistedCode } from "./src/lib/auth";
import { colors } from "./src/lib/designTokens";

export type RootStackParamList = {
  Auth: undefined;
  Home: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function App() {
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
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <>
      <StatusBar style="dark" />
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
            <Stack.Screen
              name="Home"
              options={{ headerShown: false, gestureEnabled: false }}
            >
              {() => <HomeScreen />}
            </Stack.Screen>
          )}
        </Stack.Navigator>
      </NavigationContainer>
    </>
  );
}

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    backgroundColor: colors.surface,
    justifyContent: "center",
    alignItems: "center",
  },
});
