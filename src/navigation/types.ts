export type RootStackParamList = {
  Home: undefined;
  Dictation: {
    words: string[];
    intervalSec: number;
    autoNext: boolean;
  };
  Settings: undefined;
};
