import type { FastifyInstance } from "fastify";

import {
  OpenAiApiError,
  extractWordsFromImage,
} from "../services/openai.service.js";

const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

export async function registerOcrRoutes(app: FastifyInstance): Promise<void> {
  app.post("/api/ocr/words", async (request, reply) => {
    const file = await request.file();
    if (!file) {
      return reply.status(400).send({ error: "请上传图片" });
    }

    const buffer = await file.toBuffer();
    if (buffer.byteLength > MAX_IMAGE_BYTES) {
      return reply.status(400).send({ error: "图片不能超过 8MB" });
    }

    const mimeType = file.mimetype || "image/jpeg";
    if (!mimeType.startsWith("image/")) {
      return reply.status(400).send({ error: "仅支持图片文件" });
    }

    try {
      const result = await extractWordsFromImage({
        imageBase64: buffer.toString("base64"),
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
