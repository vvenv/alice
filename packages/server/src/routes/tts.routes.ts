import type { FastifyInstance } from "fastify";

import { OpenAiApiError, synthesizeSpeech } from "../services/openai.service.js";

export async function registerTtsRoutes(app: FastifyInstance): Promise<void> {
  app.post<{
    Body: { text?: string; voice?: string; speed?: number };
  }>("/api/tts/speech", async (request, reply) => {
    const text = request.body?.text?.trim();
    if (!text) {
      return reply.status(400).send({ error: "text 不能为空" });
    }

    try {
      const { buffer, contentType } = await synthesizeSpeech({
        text,
        voice: request.body.voice,
        speed: request.body.speed,
      });
      return reply
        .header("Content-Type", contentType)
        .header("Cache-Control", "no-store")
        .send(buffer);
    } catch (error) {
      if (error instanceof OpenAiApiError) {
        return reply.status(error.status).send({ error: error.message });
      }
      request.log.error(error);
      return reply.status(500).send({ error: "TTS 服务异常" });
    }
  });
}
