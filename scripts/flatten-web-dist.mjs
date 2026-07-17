#!/usr/bin/env node
/**
 * Flatten Expo web export asset paths.
 *
 * Metro/pnpm writes assets under:
 *   assets/node_modules/.pnpm/@scope+pkg@…/node_modules/…/File.hash.ext
 *
 * Nginx (and many WAFs) deny URL path segments that start with `.`
 * (e.g. `location ~ /\. { deny all; }`), so `/.pnpm/` returns 403/404.
 *
 * This script moves every file to `assets/<basename>` (hashes make names
 * unique) and rewrites matching URL strings in the exported JS/HTML/JSON.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIST = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(ROOT, "dist");
const ASSETS = path.join(DIST, "assets");

function walkFiles(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) walkFiles(full, out);
    else out.push(full);
  }
  return out;
}

function rimraf(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

if (!fs.existsSync(ASSETS)) {
  console.log("flatten-web-dist: no assets/ — nothing to do");
  process.exit(0);
}

const files = walkFiles(ASSETS);
const moves = []; // { fromRel, toRel, basename }

for (const abs of files) {
  const rel = path.relative(DIST, abs).split(path.sep).join("/");
  const basename = path.basename(abs);
  // Already flat: assets/<file>
  if (rel === `assets/${basename}`) continue;
  moves.push({
    fromRel: rel,
    toRel: `assets/${basename}`,
    abs,
    basename,
  });
}

if (moves.length === 0) {
  console.log("flatten-web-dist: assets already flat");
  process.exit(0);
}

const basenames = moves.map((m) => m.basename);
const dupes = basenames.filter((b, i) => basenames.indexOf(b) !== i);
if (dupes.length) {
  console.error(
    "flatten-web-dist: duplicate basenames, cannot flatten:",
    [...new Set(dupes)].join(", "),
  );
  process.exit(1);
}

const staging = path.join(DIST, ".assets-flat-tmp");
rimraf(staging);
fs.mkdirSync(staging, { recursive: true });

for (const m of moves) {
  fs.copyFileSync(m.abs, path.join(staging, m.basename));
}

// Remove deep trees under assets/, keep only flat copies + any already-flat files
for (const ent of fs.readdirSync(ASSETS, { withFileTypes: true })) {
  const full = path.join(ASSETS, ent.name);
  if (ent.isDirectory()) rimraf(full);
  else if (moves.some((m) => m.basename === ent.name)) fs.unlinkSync(full);
}

for (const m of moves) {
  fs.renameSync(path.join(staging, m.basename), path.join(ASSETS, m.basename));
}
rimraf(staging);

// Longest-first so nested prefixes don't partially rewrite
const replacements = moves
  .map((m) => [m.fromRel, m.toRel])
  .sort((a, b) => b[0].length - a[0].length);

const textExt = new Set([".js", ".html", ".json", ".css", ".map"]);
const rewriteRoots = [DIST];
let rewriteCount = 0;

for (const root of rewriteRoots) {
  for (const abs of walkFiles(root)) {
    if (abs.includes(`${path.sep}.assets-flat-tmp${path.sep}`)) continue;
    if (!textExt.has(path.extname(abs))) continue;
    let text = fs.readFileSync(abs, "utf8");
    let changed = false;
    for (const [from, to] of replacements) {
      if (text.includes(from)) {
        text = text.split(from).join(to);
        changed = true;
      }
      // URL-encoded @ in path segments
      const fromEnc = from.replaceAll("@", "%40");
      const toEnc = to.replaceAll("@", "%40");
      if (fromEnc !== from && text.includes(fromEnc)) {
        text = text.split(fromEnc).join(toEnc);
        changed = true;
      }
    }
    if (changed) {
      fs.writeFileSync(abs, text);
      rewriteCount++;
    }
  }
}

console.log(
  `flatten-web-dist: flattened ${moves.length} assets, rewrote ${rewriteCount} file(s)`,
);
