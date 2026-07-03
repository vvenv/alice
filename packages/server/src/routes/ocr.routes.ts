import type { OcrWordsRequest } from "@alice/shared";
import type { FastifyInstance } from "fastify";

import {
  OpenAiApiError,
  extractWordsFromImage,
} from "../services/openai.service.js";

const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

export async function registerOcrRoutes(app: FastifyInstance): Promise<void> {
  app.post<{ Body: OcrWordsRequest }>("/api/ocr/words", async (request, reply) => {
    const imageBase64 = request.body?.image_base64?.trim();
    if (!imageBase64) {
      return reply.status(400).send({ error: "请上传图片" });
    }

    let buffer: Buffer;
    try {
      buffer = Buffer.from(imageBase64, "base64");
    } catch {
      return reply.status(400).send({ error: "图片数据无效" });
    }

    if (buffer.byteLength === 0) {
      return reply.status(400).send({ error: "请上传图片" });
    }
    if (buffer.byteLength > MAX_IMAGE_BYTES) {
      return reply.status(400).send({ error: "图片不能超过 8MB" });
    }

    const mimeType = request.body.mime_type?.startsWith("image/")
      ? request.body.mime_type
      : "image/jpeg";

    try {
      const result = await extractWordsFromImage({
        imageBase64: imageBase64,
        mimeType,
      });
      return reply.send({
        data: {
          words: result.words,
          raw_text: result.rawText,
        },
      });
    } catch (error) {
      if (error instanceof OpenAiApiError) {
        return reply.status(error.status).send({ error: error.message });
      }
      request.log.error(error);
      return reply.status(500).send({ error: "OCR 服务异常" });
    }
  });
}
