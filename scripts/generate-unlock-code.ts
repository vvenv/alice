/**
 * Generate valid unlock codes for Alice Dictation OCR feature.
 *
 * Usage:
 *   npx tsx scripts/generate-unlock-code.ts
 *   npx tsx scripts/generate-unlock-code.ts --count 5
 *   npx tsx scripts/generate-unlock-code.ts --secret "your-secret-key"
 */

import { hmacSha256Hex } from "../src/lib/crypto";

/* ---- CLI ---- */

const ALPHANUMERIC = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/I/1 to avoid confusion

function randomAlphanumeric(len: number): string {
  let result = "";
  for (let i = 0; i < len; i++) {
    result += ALPHANUMERIC[Math.floor(Math.random() * ALPHANUMERIC.length)];
  }
  return result;
}

function generateCode(secret: string, prefix: string): string {
  for (let attempts = 0; ; attempts++) {
    const code = randomAlphanumeric(4);
    const hex = hmacSha256Hex(secret, code);
    if (hex.startsWith(prefix)) {
      return code;
    }
    if (attempts > 0 && attempts % 10000 === 0) {
      console.error(`  ... ${attempts} attempts so far`);
    }
  }
}

function main() {
  const args = process.argv.slice(2);
  let secret = "YOUR_HMAC_SECRET";
  let count = 1;
  let prefix = "00";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--secret" && i + 1 < args.length) {
      secret = args[++i];
    } else if (args[i] === "--count" && i + 1 < args.length) {
      count = parseInt(args[++i], 10);
    } else if (args[i] === "--prefix" && i + 1 < args.length) {
      prefix = args[++i];
    } else if (args[i] === "--help" || args[i] === "-h") {
      console.log("Usage: npx tsx scripts/generate-unlock-code.ts [options]");
      console.log("  --secret <key>    HMAC secret (default: alice-dictation-default-secret)");
      console.log("  --count <n>       Number of codes to generate (default: 1)");
      console.log("  --prefix <hex>    Required hex prefix (default: 00)");
      process.exit(0);
    }
  }

  console.log(`Secret: ${secret}`);
  console.log(`Prefix: ${prefix}`);
  console.log(`Count:  ${count}`);
  console.log("");

  const codes: string[] = [];
  for (let i = 0; i < count; i++) {
    const code = generateCode(secret, prefix);
    codes.push(code);
    console.log(`  ${i + 1}. ${code}`);
    // verify
    const hex = hmacSha256Hex(secret, code);
    console.log(`     HMAC: ${hex.slice(0, 16)}... (starts with "${hex.slice(0, 2)}" ✓)`);
    console.log("");
  }

  if (count > 1) {
    console.log("All codes:", codes.join(", "));
  }
}

main();
