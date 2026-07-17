// Dynamic Expo config: merges gitignored secrets from .env / process.env
// into the static app.json so they never live in the repo.
const fs = require("fs");
const path = require("path");

/** Minimal .env loader (no dotenv dependency); process.env wins. */
function loadEnvFile() {
  const envPath = path.join(__dirname, ".env");
  if (!fs.existsSync(envPath)) return {};
  const out = {};
  for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m) out[m[1]] = m[2].replace(/^(['"])(.*)\1$/, "$2");
  }
  return out;
}

const env = { ...loadEnvFile(), ...process.env };

// Web bundles are public JS — never embed a shared OCR key.
const isWebBuild =
  process.env.ALICE_WEB_BUILD === "1" ||
  process.argv.some((a, i, arr) => a === "web" || (a === "--platform" && arr[i + 1] === "web"));

module.exports = ({ config }) => ({
  ...config,
  extra: {
    ...config.extra,
    zhipuApiKey: isWebBuild ? "" : (env.ZHIPU_API_KEY ?? ""),
  },
});
