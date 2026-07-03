import cors from "@fastify/cors";
import multipart from "@fastify/multipart";
import Fastify, { type FastifyInstance } from "fastify";

import { config } from "./lib/config.js";
import { registerOcrRoutes } from "./routes/ocr.routes.js";
import { registerTtsRoutes } from "./routes/tts.routes.js";

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: config.server.logLevel },
    trustProxy: true,
    bodyLimit: 10 * 1024 * 1024,
  });

  await app.register(cors, { origin: true });
  await app.register(multipart, {
    limits: { fileSize: 8 * 1024 * 1024 },
  });

  app.get("/health", async () => ({ status: "ok" }));

  await registerTtsRoutes(app);
  await registerOcrRoutes(app);

  return app;
}
