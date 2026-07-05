export type RootStackParamList = {
  Auth: undefined;
  Home: undefined;
  Dictation: {
    words: string[];
    intervalSec: number;
    autoNext: boolean;
  };
};
