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

module.exports = ({ config }) => ({
  ...config,
  extra: {
    ...config.extra,
    zhipuApiKey: env.ZHIPU_API_KEY ?? "",
  },
});
