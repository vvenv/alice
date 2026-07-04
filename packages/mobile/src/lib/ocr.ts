import * as ImageManipulator from "expo-image-manipulator";
import * as ImagePicker from "expo-image-picker";

import { apiFetch } from "./api";

const OCR_MAX_EDGE = 1600;
const OCR_JPEG_QUALITY = 0.82;

function uriToBase64(uri: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.onload = () => {
      const reader = new FileReader();
      reader.onload = () => {
        const result = reader.result as string;
        const commaIndex = result.indexOf(",");
        resolve(commaIndex >= 0 ? result.slice(commaIndex + 1) : result);
      };
      reader.onerror = () => reject(new Error("读取图片失败"));
      reader.readAsDataURL(xhr.response);
    };
    xhr.onerror = () => reject(new Error("读取图片失败"));
    xhr.responseType = "blob";
    xhr.open("GET", uri);
    xhr.send();
  });
}

async function compressImageForOcr(
  uri: string,
): Promise<{ base64: string; mimeType: string }> {
  // Resize if needed
  const resized = await ImageManipulator.manipulateAsync(
    uri,
    [
      {
        resize: {
          width: OCR_MAX_EDGE,
        },
      },
    ],
    {
      compress: OCR_JPEG_QUALITY,
      format: ImageManipulator.SaveFormat.JPEG,
    },
  );

  const base64 = await uriToBase64(resized.uri);
  return { base64, mimeType: "image/jpeg" };
}

export async function pickImageFromGallery(): Promise<string | null> {
  const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new Error("需要相册访问权限");
  }

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ["images"],
    quality: 1,
  });

  if (result.canceled || !result.assets.length) return null;
  return result.assets[0]!.uri;
}

export async function takePhoto(): Promise<string | null> {
  const permission = await ImagePicker.requestCameraPermissionsAsync();
  if (!permission.granted) {
    throw new Error("需要相机权限");
  }

  const result = await ImagePicker.launchCameraAsync({
    mediaTypes: ["images"],
    quality: 1,
  });

  if (result.canceled || !result.assets.length) return null;
  return result.assets[0]!.uri;
}

export async function ocrWordsFromImage(
  imageUri: string,
  onStatus?: (status: string) => void,
): Promise<{ words: string[]; rawText: string }> {
  onStatus?.("处理图片中…");
  const { base64, mimeType } = await compressImageForOcr(imageUri);

  onStatus?.("识别中…");
  const body = {
    image_base64: base64,
    mime_type: mimeType,
  };

  let response: Response;
  try {
    response = await apiFetch("/api/ocr/words", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    throw new Error("图片上传失败，请检查网络后重试");
  }

  let payload: { data: { words: string[]; raw_text: string } } | { error: string };
  try {
    payload = (await response.json()) as
      | { data: { words: string[]; raw_text: string } }
      | { error: string };
  } catch {
    throw new Error(
      response.ok ? "识别失败" : "图片上传中断，请换一张较小的图片重试",
    );
  }

  if (!response.ok || "error" in payload) {
    const message = "error" in payload ? payload.error : "识别失败";
    throw new Error(message);
  }

  return {
    words: payload.data.words,
    rawText: payload.data.raw_text,
  };
}
