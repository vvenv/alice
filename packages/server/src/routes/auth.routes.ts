import type { FastifyInstance } from "fastify";

import { isValidAccessCode } from "../lib/access-code.js";

export async function registerAuthRoutes(app: FastifyInstance): Promise<void> {
  app.post<{ Body: { code?: string } }>(
    "/api/auth/verify",
    async (request, reply) => {
      if (!isValidAccessCode(request.body?.code)) {
        return reply
          .status(401)
          .send({ error: "使用码不正确", code: "UNAUTHORIZED" });
      }
      return reply.send({ data: { ok: true } });
    },
  );
}
