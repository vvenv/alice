import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { useColorScheme } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

export type ThemeColors = {
  primary: string;
  primaryLight: string;
  primaryDark: string;
  primarySoft: string;
  primaryRing: string;
  primaryFocus: string;

  danger: string;
  dangerSoft: string;
  dangerHover: string;
  dangerMuted: string;

  foreground: string;
  background: string;

  muted: string;
  subtle: string;
  secondary: string;

  border: string;
  borderSubtle: string;
  borderMuted: string;

  surface: string;
  surfaceRaised: string;
  surfaceSunken: string;
  surfaceHover: string;
  track: string;
};

export const lightTheme: ThemeColors = {
  primary: "#4f46e5",
  primaryLight: "#6366f1",
  primaryDark: "#4338ca",
  primarySoft: "#eef2ff",
  primaryRing: "#e0e7ff",
  primaryFocus: "#818cf8",

  danger: "#e11d48",
  dangerSoft: "#fff1f2",
  dangerHover: "#ffe4e6",
  dangerMuted: "#fb7185",

  foreground: "#000000",
  background: "#ffffff",

  muted: "#00000066",
  subtle: "#00000040",
  secondary: "#000000A6",

  border: "#0000001A",
  borderSubtle: "#0000000F",
  borderMuted: "#00000013",

  surface: "#00000008",
  surfaceRaised: "#0000000B",
  surfaceSunken: "#00000005",
  surfaceHover: "#0000000A",
  track: "#00000012",
};

export const darkTheme: ThemeColors = {
  primary: "#818cf8",
  primaryLight: "#a5b4fc",
  primaryDark: "#6366f1",
  primarySoft: "#1e1b4b",
  primaryRing: "#312e81",
  primaryFocus: "#6366f1",

  danger: "#fb7185",
  dangerSoft: "#2d1520",
  dangerHover: "#3d1f2a",
  dangerMuted: "#e11d48",

  foreground: "#ffffff",
  background: "#0f0f11",

  muted: "#ffffff66",
  subtle: "#ffffff40",
  secondary: "#ffffffA6",

  border: "#ffffff1A",
  borderSubtle: "#ffffff0F",
  borderMuted: "#ffffff13",

  surface: "#ffffff08",
  surfaceRaised: "#ffffff0B",
  surfaceSunken: "#ffffff05",
  surfaceHover: "#ffffff0A",
  track: "#ffffff12",
};

type ThemeMode = "light" | "dark";

interface ThemeContextValue {
  colors: ThemeColors;
  mode: ThemeMode;
  toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextValue>({
  colors: lightTheme,
  mode: "light",
  toggleTheme: () => {},
});

const THEME_KEY = "alice_theme_mode";

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const systemScheme = useColorScheme();
  const [mode, setMode] = useState<ThemeMode>("light");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        const stored = await AsyncStorage.getItem(THEME_KEY);
        if (stored === "dark" || stored === "light") {
          setMode(stored);
        } else if (systemScheme) {
          setMode(systemScheme === "dark" ? "dark" : "light");
        }
      } catch {
        // ignore
      }
      setReady(true);
    })();
  }, [systemScheme]);

  useEffect(() => {
    if (systemScheme && !ready) return;
    // Sync system preference if no explicit user choice
    if (!systemScheme) return;
    AsyncStorage.getItem(THEME_KEY).then((stored) => {
      if (!stored && systemScheme !== mode) {
        setMode(systemScheme === "dark" ? "dark" : "light");
      }
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [systemScheme]);

  const toggleTheme = useCallback(() => {
    setMode((prev) => {
      const next = prev === "dark" ? "light" : "dark";
      AsyncStorage.setItem(THEME_KEY, next).catch(() => {});
      return next;
    });
  }, []);

  const colors = mode === "dark" ? darkTheme : lightTheme;

  return (
    <ThemeContext.Provider value={{ colors, mode, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useThemeColors(): ThemeColors {
  return useContext(ThemeContext).colors;
}

export function useThemeMode(): { mode: ThemeMode; toggleTheme: () => void } {
  const { mode, toggleTheme } = useContext(ThemeContext);
  return { mode, toggleTheme };
}
