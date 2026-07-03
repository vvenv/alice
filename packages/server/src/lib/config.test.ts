import { describe, expect, it } from "vitest";

import { config } from "./config.js";

describe("config", () => {
  it("has default server port", () => {
    expect(config.server.port).toBeGreaterThan(0);
  });
});
