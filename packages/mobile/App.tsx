import { useEffect, useState } from "react";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { ActivityIndicator, StyleSheet, View } from "react-native";
import { StatusBar } from "expo-status-bar";

import { AuthScreen } from "./src/screens/AuthScreen";
import { HomeScreen } from "./src/screens/HomeScreen";
import { DictationScreen } from "./src/screens/DictationScreen";
import { loadPersistedCode } from "./src/lib/auth";
import { loadPersistedWrongWords } from "./src/lib/storage";

export type RootStackParamList = {
  Auth: undefined;
  Home: undefined;
  Dictation: {
    words: string[];
    voice: string;
    intervalSec: number;
    autoNext: boolean;
    brokenWords: string[];
  };
};

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function App() {
  const [ready, setReady] = useState(false);
  const [authed, setAuthed] = useState(false);
  const [brokenWords, setBrokenWords] = useState<string[]>([]);

  useEffect(() => {
    (async () => {
      const code = await loadPersistedCode();
      setAuthed(code !== null);
      const wrong = await loadPersistedWrongWords();
      setBrokenWords(wrong);
      setReady(true);
    })();
  }, []);

  if (!ready) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#4a6cf7" />
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
              {(props) => (
                <AuthScreen
                  onAuthenticated={() => setAuthed(true)}
                />
              )}
            </Stack.Screen>
          ) : (
            <>
              <Stack.Screen
                name="Home"
                options={{ headerShown: false }}
              >
                {({ navigation }) => (
                  <HomeScreen
                    onStartDictation={(params) =>
                      navigation.navigate("Dictation", {
                        ...params,
                        brokenWords,
                      })
                    }
                  />
                )}
              </Stack.Screen>
              <Stack.Screen
                name="Dictation"
                options={{
                  headerShown: false,
                  gestureEnabled: false, // prevent swipe-back during dictation
                }}
              >
                {({ route, navigation }) => (
                  <DictationScreen
                    words={route.params.words}
                    voice={route.params.voice}
                    intervalSec={route.params.intervalSec}
                    autoNext={route.params.autoNext}
                    brokenWords={route.params.brokenWords}
                    onEnd={() => navigation.goBack()}
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

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    backgroundColor: "#f8f9fa",
    justifyContent: "center",
    alignItems: "center",
  },
});
