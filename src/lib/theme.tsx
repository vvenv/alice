import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import { useColorScheme } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

export type ThemeColors = {
  primary: string;
  primarySoft: string;

  /** Wonderland gold accent — used for instrument/readout elements (timers, progress). */
  gold: string;
  goldSoft: string;

  /** Wonderland rose accent — used for italic flourishes and danger states. */
  rose: string;
  roseSoft: string;

  danger: string;
  dangerSoft: string;
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
  track: string;

  overlay: string;
};

export const lightTheme: ThemeColors = {
  // Wonderland "paper" theme: ink on paper, gold highlights, rose danger.
  primary: "#1A2B4A", // ink — primary actions (ink bg + paper text)
  primarySoft: "#F4ECD6", // warm gold tint — active/selected highlights

  gold: "#B8860B",
  goldSoft: "#F4ECD6",

  rose: "#C44569",
  roseSoft: "#F6E4EA",

  danger: "#C44569", // rose
  dangerSoft: "#F6E4EA",
  dangerMuted: "#B8385E",

  foreground: "#1A2B4A", // ink
  background: "#FAF6EE", // paper

  muted: "#1A2B4ACC",
  subtle: "#1A2B4AB3",
  secondary: "#1A2B4ABF",

  border: "#1A2B4A1A",
  borderSubtle: "#1A2B4A0F",
  borderMuted: "#1A2B4A13",

  surface: "#F2EBDA", // parchment — flat chips/buttons
  surfaceRaised: "#FFFEF9", // lifted cards
  surfaceSunken: "#EFE6CF", // recessed inputs/panels
  track: "#1A2B4A1A",

  overlay: "rgba(15,26,46,0.5)",
};

export const darkTheme: ThemeColors = {
  // Wonderland "midnight" theme: paper on midnight, slate (lightened ink) primary,
  // gold reserved for instrument readouts, rose danger. Cool & calm like the light theme.
  primary: "#C5D0E0", // soft slate (lightened ink) — primary actions (slate bg + midnight text)
  primarySoft: "#243352", // dark slate tint — active/selected highlights

  gold: "#D4A437", // accent only — progress/countdown (gold hands on a dark watch face)
  goldSoft: "#2A2410",

  rose: "#E06488",
  roseSoft: "#2E1620",

  danger: "#E06488", // rose
  dangerSoft: "#2E1620",
  dangerMuted: "#E06488",

  foreground: "#FAF6EE", // paper
  background: "#0F1A2E", // midnight

  muted: "#FAF6EEBF",
  subtle: "#FAF6EE99",
  secondary: "#FAF6EEBF",

  border: "#FAF6EE1A",
  borderSubtle: "#FAF6EE0F",
  borderMuted: "#FAF6EE13",

  surface: "#162238", // nightpaper — flat chips/buttons
  surfaceRaised: "#1B2A42", // lifted cards
  surfaceSunken: "#0C1626", // recessed inputs/panels
  track: "#FAF6EE1A",

  overlay: "rgba(0,0,0,0.6)",
};

type ThemeMode = "light" | "dark";

interface ThemeContextValue {
  colors: ThemeColors;
  mode: ThemeMode;
  toggleTheme: () => void;
  setMode: (mode: ThemeMode) => void;
}

const ThemeContext = createContext<ThemeContextValue>({
  colors: lightTheme,
  mode: "light",
  toggleTheme: () => {},
  setMode: () => {},
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

  const setThemeMode = useCallback((next: ThemeMode) => {
    setMode((prev) => {
      if (prev === next) return prev;
      AsyncStorage.setItem(THEME_KEY, next).catch(() => {});
      return next;
    });
  }, []);

  const colors = mode === "dark" ? darkTheme : lightTheme;

  return (
    <ThemeContext.Provider
      value={{ colors, mode, toggleTheme, setMode: setThemeMode }}
    >
      {children}
    </ThemeContext.Provider>
  );
}

export function useThemeColors(): ThemeColors {
  return useContext(ThemeContext).colors;
}

export function useThemeMode(): {
  mode: ThemeMode;
  toggleTheme: () => void;
  setMode: (mode: ThemeMode) => void;
} {
  const { mode, toggleTheme, setMode } = useContext(ThemeContext);
  return { mode, toggleTheme, setMode };
}
