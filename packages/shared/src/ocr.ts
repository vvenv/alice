export type OcrWordsRequest = {
  image_base64: string;
  mime_type?: string;
};

export type OcrWordsResponse = {
  words: string[];
  raw_text: string;
};
