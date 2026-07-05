/**
 * Minimal HMAC-SHA256 implementation in pure TypeScript.
 * No external dependencies required.
 */

/* ---------- SHA-256 ---------- */

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

function rr(x: number, n: number): number {
  return (x >>> n) | (x << (32 - n));
}

function sha256(msg: Uint8Array): Uint8Array {
  const H = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);

  const ml = msg.length * 8;
  // pad: append 0x80, then zeros, then 64-bit length
  const padLen = ((msg.length + 9 + 63) & ~63);
  const m = new Uint8Array(padLen);
  m.set(msg);
  m[msg.length] = 0x80;
  const dv = new DataView(m.buffer);
  dv.setUint32(padLen - 4, ml >>> 0, false);
  dv.setUint32(padLen - 8, Math.floor(ml / 0x100000000), false);

  const W = new Uint32Array(64);
  for (let off = 0; off < padLen; off += 64) {
    for (let t = 0; t < 16; t++) {
      W[t] = dv.getUint32(off + t * 4, false);
    }
    for (let t = 16; t < 64; t++) {
      const s0 = rr(W[t - 15], 7) ^ rr(W[t - 15], 18) ^ (W[t - 15] >>> 3);
      const s1 = rr(W[t - 2], 17) ^ rr(W[t - 2], 19) ^ (W[t - 2] >>> 10);
      W[t] = (W[t - 16] + s0 + W[t - 7] + s1) >>> 0;
    }

    let a = H[0], b = H[1], c = H[2], d = H[3];
    let e = H[4], f = H[5], g = H[6], h = H[7];

    for (let t = 0; t < 64; t++) {
      const S1 = rr(e, 6) ^ rr(e, 11) ^ rr(e, 25);
      const ch = (e & f) ^ ((~e) & g);
      const temp1 = (h + S1 + ch + K[t] + W[t]) >>> 0;
      const S0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (S0 + maj) >>> 0;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }

    H[0] = (H[0] + a) >>> 0;
    H[1] = (H[1] + b) >>> 0;
    H[2] = (H[2] + c) >>> 0;
    H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0;
    H[5] = (H[5] + f) >>> 0;
    H[6] = (H[6] + g) >>> 0;
    H[7] = (H[7] + h) >>> 0;
  }

  const out = new Uint8Array(32);
  const dvOut = new DataView(out.buffer);
  for (let i = 0; i < 8; i++) {
    dvOut.setUint32(i * 4, H[i], false);
  }
  return out;
}

function toBytes(s: string): Uint8Array {
  const enc = new TextEncoder();
  return enc.encode(s);
}

function bytesToHex(b: Uint8Array): string {
  return Array.from(b).map((x) => x.toString(16).padStart(2, "0")).join("");
}

function xor(a: Uint8Array, b: Uint8Array): Uint8Array {
  const r = new Uint8Array(a.length);
  for (let i = 0; i < a.length; i++) r[i] = a[i] ^ b[i];
  return r;
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const r = new Uint8Array(a.length + b.length);
  r.set(a);
  r.set(b, a.length);
  return r;
}

const BLOCK_SIZE = 64; // bytes for SHA256

/**
 * Compute HMAC-SHA256 and return hex string.
 */
export function hmacSha256Hex(key: string, data: string): string {
  let keyBytes = toBytes(key);

  // If key is longer than block size, hash it first
  if (keyBytes.length > BLOCK_SIZE) {
    keyBytes = sha256(keyBytes);
  }

  // Pad key to block size
  const paddedKey = new Uint8Array(BLOCK_SIZE);
  paddedKey.set(keyBytes);

  const ipad = xor(paddedKey, new Uint8Array(BLOCK_SIZE).fill(0x36));
  const opad = xor(paddedKey, new Uint8Array(BLOCK_SIZE).fill(0x5c));

  const inner = sha256(concat(ipad, toBytes(data)));
  const outer = sha256(concat(opad, inner));

  return bytesToHex(outer);
}
