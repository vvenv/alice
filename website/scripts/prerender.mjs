/**
 * Post-build prerender: SSR-build src/entry-server.tsx, render / with
 * react-dom/server, write the markup into dist/index.html.
 *
 * The markup has to come from React (not a browser DOM snapshot), otherwise
 * hydrateRoot in main.tsx fails with a hydration mismatch.
 */
import { readFileSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { build } from "vite";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const DIST = join(ROOT, "dist");
const SSR_DIST = join(ROOT, "dist-ssr");
const INDEX = join(DIST, "index.html");
const EMPTY_ROOT = '<div id="root"></div>';

async function main() {
  if (!existsSync(INDEX)) {
    throw new Error(`Missing ${INDEX} — run vite build first`);
  }

  let html = readFileSync(INDEX, "utf8");
  if (!html.includes(EMPTY_ROOT)) {
    throw new Error(
      "dist/index.html has no empty #root (already prerendered?) — run vite build first",
    );
  }

  try {
    await build({
      root: ROOT,
      logLevel: "warn",
      build: {
        ssr: "src/entry-server.tsx",
        outDir: SSR_DIST,
        emptyOutDir: true,
        sourcemap: false,
      },
    });

    const { render } = await import(
      pathToFileURL(join(SSR_DIST, "entry-server.js")).href
    );
    const rootHtml = render();
    if (!rootHtml || rootHtml.length < 200 || !rootHtml.includes("<h1")) {
      throw new Error("Prerender produced unexpectedly empty #root");
    }

    // Function replacer: rootHtml may contain `$` sequences.
    html = html.replace(EMPTY_ROOT, () => `<div id="root">${rootHtml}</div>`);

    writeFileSync(INDEX, html);
    console.log(`✓ Prerendered / → ${INDEX} (${rootHtml.length} chars in #root)`);
  } finally {
    rmSync(SSR_DIST, { recursive: true, force: true });
  }
}

main().catch((err) => {
  console.error("Prerender failed:", err);
  process.exit(1);
});
