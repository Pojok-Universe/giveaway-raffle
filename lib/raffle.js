import crypto from "node:crypto";

// PRNG mulberry32 — deterministik dari seed integer
function mulberry32(seedInt) {
  let a = seedInt >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Kocok pool entry lalu ambil N pemenang. Hasil bisa direproduksi dari seed.
export function drawWinners(entryIds, count, seedHex) {
  const seedInt = parseInt(
    crypto.createHash("sha256").update(seedHex).digest("hex").slice(0, 8),
    16
  );
  const rand = mulberry32(seedInt);
  const pool = [...entryIds];
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  return pool.slice(0, Math.min(count, pool.length));
}

export function newSeed() {
  return crypto.randomBytes(16).toString("hex");
}
