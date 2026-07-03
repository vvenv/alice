import { buildApp } from "./app.js";
import { config } from "./lib/config.js";

async function bootstrap(): Promise<void> {
  const app = await buildApp();
  const { port, host } = config.server;

  try {
    await app.listen({ port, host });
    app.log.info(`alice server listening on ${host}:${port}`);
  } catch (error) {
    app.log.error(error);
    process.exit(1);
  }
}

void bootstrap();
