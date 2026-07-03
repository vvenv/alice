import cors from "@fastify/cors";
import Fastify, { type FastifyInstance } from "fastify";

import { config } from "./lib/config.js";
import { registerOcrRoutes } from "./routes/ocr.routes.js";
import { registerTtsRoutes } from "./routes/tts.routes.js";

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: config.server.logLevel },
    trustProxy: true,
    bodyLimit: 12 * 1024 * 1024,
  });

  await app.register(cors, { origin: true });

  app.get("/health", async () => ({ status: "ok" }));

  await registerTtsRoutes(app);
  await registerOcrRoutes(app);

  return app;
}
