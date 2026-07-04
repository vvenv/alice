import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";

import { config } from "./config.js";

const ACCESS_CODE_HEADER = "x-access-code";

export function isValidAccessCode(code: unknown): boolean {
  return typeof code === "string" && code === config.accessCode;
}

function unauthorized(reply: FastifyReply) {
  return reply
    .status(401)
    .send({ error: "使用码无效", code: "UNAUTHORIZED" });
}

/** 校验 /api/*（除 /api/auth/verify）请求头中的使用码。 */
export async function registerAccessCodeAuth(
  app: FastifyInstance,
): Promise<void> {
  app.addHook("onRequest", async (request: FastifyRequest, reply) => {
    const path = request.url.split("?")[0] ?? "";
    if (!path.startsWith("/api/")) return;
    if (path === "/api/auth/verify") return;

    const code = request.headers[ACCESS_CODE_HEADER];
    if (!isValidAccessCode(code)) {
      return unauthorized(reply);
    }
  });
}
