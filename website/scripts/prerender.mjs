/**
 * Post-build prerender: serve dist/, render /, write HTML into dist/index.html.
 */
import { createServer } from "node:http";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, extname, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIST = join(__dirname, "..", "dist");
const INDEX = join(DIST, "index.html");
const PORT = 4179;

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".json": "application/json",
  ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml",
  ".map": "application/json",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function contentType(filePath) {
  return MIME[extname(filePath).toLowerCase()] ?? "application/octet-stream";
}

function startServer() {
  return new Promise((resolve, reject) => {
    const server = createServer((req, res) => {
      try {
        const url = new URL(req.url ?? "/", `http://127.0.0.1:${PORT}`);
        let pathname = decodeURIComponent(url.pathname);
        if (pathname.endsWith("/")) pathname += "index.html";
        const filePath = join(DIST, pathname === "/" ? "index.html" : pathname.slice(1));
        if (!filePath.startsWith(DIST) || !existsSync(filePath)) {
          res.writeHead(404);
          res.end("Not found");
          return;
        }
        res.writeHead(200, { "Content-Type": contentType(filePath) });
        res.end(readFileSync(filePath));
      } catch (err) {
        res.writeHead(500);
        res.end(String(err));
      }
    });
    server.listen(PORT, "127.0.0.1", () => resolve(server));
    server.on("error", reject);
  });
}

async function main() {
  if (!existsSync(INDEX)) {
    throw new Error(`Missing ${INDEX} — run vite build first`);
  }

  const server = await startServer();
  const browser = await chromium.launch({ headless: true });

  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${PORT}/`, {
      waitUntil: "networkidle",
      timeout: 60_000,
    });
    await page.waitForSelector("#root h1", { timeout: 30_000 });

    const rootHtml = await page.$eval("#root", (el) => el.innerHTML);
    if (!rootHtml || rootHtml.length < 200) {
      throw new Error("Prerender produced unexpectedly empty #root");
    }

    let html = readFileSync(INDEX, "utf8");
    if (!html.includes('<div id="root"></div>') && !html.includes('<div id="root">')) {
      throw new Error("dist/index.html does not contain a recognizable #root");
    }

    html = html.replace(
      /<div id="root">[\s\S]*?<\/div>/,
      `<div id="root">${rootHtml}</div>`,
    );

    writeFileSync(INDEX, html);
    console.log(`✓ Prerendered / → ${INDEX} (${rootHtml.length} chars in #root)`);
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((err) => {
  console.error("Prerender failed:", err);
  process.exit(1);
});
