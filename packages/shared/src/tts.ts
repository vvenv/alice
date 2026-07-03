export type TtsSpeechRequest = {
  text: string;
  voice?: string;
  speed?: number;
};

export type TtsSpeechResponse = {
  content_type: string;
};
