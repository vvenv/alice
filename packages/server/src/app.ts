import path from "path";
import { fileURLToPath } from "url";

import cors from "@fastify/cors";
import fastifyStatic from "@fastify/static";
import Fastify, { type FastifyInstance } from "fastify";

import { config } from "./lib/config.js";
import { registerOcrRoutes } from "./routes/ocr.routes.js";
import { registerTtsRoutes } from "./routes/tts.routes.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const clientDist = path.resolve(__dirname, "../../client/dist");

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

  // 前端 SPA 静态文件
  await app.register(fastifyStatic, {
    root: clientDist,
    prefix: "/",
    wildcard: false,
  });

  // SPA fallback：非 /api/ 路径都返回 index.html 交由前端路由处理
  app.setNotFoundHandler((request, reply) => {
    if (request.url.startsWith("/api/")) {
      return reply.status(404).send({ error: "Not Found" });
    }
    return reply.sendFile("index.html");
  });

  return app;
}
