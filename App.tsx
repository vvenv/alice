import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { StatusBar } from "expo-status-bar";

import type { RootStackParamList } from "./src/navigation/types";
import { DictationScreen } from "./src/screens/DictationScreen";
import { HomeScreen } from "./src/screens/HomeScreen";
import { SettingsScreen } from "./src/screens/SettingsScreen";
import { ThemeProvider, useThemeMode } from "./src/lib/theme";

export type { RootStackParamList };

const Stack = createNativeStackNavigator<RootStackParamList>();

function AppContent() {
  const { mode } = useThemeMode();

  return (
    <>
      <StatusBar style={mode === "dark" ? "light" : "dark"} />
      <NavigationContainer>
        <Stack.Navigator
          screenOptions={{
            headerShown: false,
            animation: "slide_from_right",
          }}
        >
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
          <Stack.Screen
            name="Settings"
            options={{ headerShown: false, gestureEnabled: true }}
          >
            {() => <SettingsScreen />}
          </Stack.Screen>
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
